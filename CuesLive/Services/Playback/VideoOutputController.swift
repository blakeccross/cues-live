import AVFoundation
import Foundation
import Observation
import os

/// Plays the active song's movie for the Video window, locked to that song's audio engine.
///
/// Screens that own playback (the live setlist, a song editor that owns the engine) claim the
/// output with their song and engine; the most recent claim wins and releasing it hands the
/// output back to the one before. The movie is only decoded while a Video window is open.
@MainActor
@Observable
final class VideoOutputController {
    static let shared = VideoOutputController()

    private struct Claim {
        let owner: UUID
        var placement: VideoPlacement?
        var songName: String
        var isVideoMissing: Bool
        var engine: AudioEngineManager
    }

    /// The movie on display, nil when the active song has no video.
    private(set) var placement: VideoPlacement?
    private(set) var songName: String?
    /// True when the active song has a video whose file cannot be found.
    private(set) var isVideoMissing = false
    /// Picture size of the movie on display, for the window's aspect.
    private(set) var info: VideoFileInfo?
    /// False while the playhead is outside the movie; the window shows black then.
    private(set) var isPictureVisible = false
    private(set) var openWindowCount = 0

    /// Shared by every Video window's player layer.
    @ObservationIgnored let player: AVPlayer = {
        let player = AVPlayer()
        player.isMuted = true
        // Required for `setRate(_:time:atHostTime:)`, which locks the picture to the host clock.
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        return player
    }()

    @ObservationIgnored private var claims: [Claim] = []
    @ObservationIgnored private var engine: AudioEngineManager?
    @ObservationIgnored private var syncTimer: Timer?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var lastLock = Date.distantPast
    @ObservationIgnored private var infoTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "live.cues", category: "Video")
    private static let syncInterval: TimeInterval = 1.0 / 60.0
    private static let timescale: CMTimeScale = 600

    // MARK: - Claims

    /// Shows `song`'s movie, following `engine`. Calling again with the same owner updates the claim in place.
    func claim(_ owner: UUID, song: Song?, engine: AudioEngineManager) {
        let placement = song.flatMap(VideoPlacement.init(song:))
        let claim = Claim(
            owner: owner,
            placement: placement,
            songName: song?.name ?? "",
            isVideoMissing: song?.videoTrack != nil && placement == nil,
            engine: engine
        )
        if let index = claims.firstIndex(where: { $0.owner == owner }) {
            claims[index] = claim
        } else {
            claims.append(claim)
        }
        applyActiveClaim()
    }

    func release(_ owner: UUID) {
        claims.removeAll { $0.owner == owner }
        applyActiveClaim()
    }

    func windowDidAppear() {
        openWindowCount += 1
        updateSyncTimer()
    }

    func windowDidDisappear() {
        openWindowCount = max(0, openWindowCount - 1)
        updateSyncTimer()
    }

    private func applyActiveClaim() {
        let active = claims.last
        engine = active?.engine
        songName = active?.songName
        isVideoMissing = active?.isVideoMissing ?? false
        let next = active?.placement
        guard next != placement else { return }
        let urlChanged = next?.url != placement?.url
        placement = next
        if urlChanged {
            replaceItem(with: next?.url)
        }
        updateSyncTimer()
    }

    private func replaceItem(with url: URL?) {
        infoTask?.cancel()
        info = nil
        isPictureVisible = false
        isSeeking = false
        lastLock = .distantPast
        player.pause()
        guard let url else {
            player.replaceCurrentItem(with: nil)
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        infoTask = Task { [weak self] in
            let info = await FileStore.videoInfo(at: url)
            guard !Task.isCancelled else { return }
            self?.info = info
        }
    }

    // MARK: - Sync

    private func updateSyncTimer() {
        let shouldRun = openWindowCount > 0 && placement != nil
        if shouldRun, syncTimer == nil {
            let timer = Timer(timeInterval: Self.syncInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncTick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            syncTimer = timer
        } else if !shouldRun, let syncTimer {
            syncTimer.invalidate()
            self.syncTimer = nil
            player.pause()
        }
    }

    private func syncTick() {
        guard let placement, let engine, player.currentItem?.status == .readyToPlay else { return }
        // Songs saved before the movie was first read have no length yet; the file has one.
        let bounded = VideoPlacement(
            url: placement.url,
            startSeconds: placement.startSeconds,
            durationSeconds: placement.durationSeconds ?? info?.durationSeconds
        )
        let target = bounded.movieSeconds(atTimeline: engine.livePlayheadTime())
        let state = VideoSyncPolicy.PlayerState(
            seconds: player.currentTime().seconds,
            isRunning: player.rate != 0,
            isSeeking: isSeeking,
            secondsSinceLastLock: Date().timeIntervalSince(lastLock)
        )
        apply(VideoSyncPolicy.action(target: target, isTransportPlaying: engine.isPlaying, player: state))
    }

    private func apply(_ action: VideoSyncAction) {
        switch action {
        case .none:
            break
        case .hide:
            if player.rate != 0 {
                player.pause()
            }
            isPictureVisible = false
        case .play(let seconds):
            player.setRate(1, time: Self.time(seconds), atHostTime: CMClockGetTime(CMClockGetHostTimeClock()))
            lastLock = Date()
            isPictureVisible = true
        case .pause(let seconds):
            player.pause()
            seek(to: seconds)
        case .seek(let seconds):
            seek(to: seconds)
        }
    }

    private func seek(to seconds: TimeInterval) {
        isSeeking = true
        isPictureVisible = true
        player.seek(to: Self.time(seconds), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                self?.isSeeking = false
                if !finished {
                    Self.logger.debug("Video seek interrupted")
                }
            }
        }
    }

    private static func time(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: max(0, seconds), preferredTimescale: timescale)
    }
}
