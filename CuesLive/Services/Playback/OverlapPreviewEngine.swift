import AVFoundation
import Foundation
import Observation

/// Previews an overlap transition by playing the outgoing and incoming songs on
/// two independent `AudioEngineManager` instances (same approach as live overlap).
@Observable
final class OverlapPreviewEngine {
    private let outgoingEngine = AudioEngineManager()
    private let incomingEngine = AudioEngineManager()

    private var playbackTimer: Timer?
    private var loadGeneration = 0
    private var incomingStarted = false

    private var previewStartTime: TimeInterval = 0
    private var incomingLaneOffset: TimeInterval = 0
    private var previewDuration: TimeInterval = 0

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var isLoaded = false
    private(set) var loadError: String?

    deinit {
        teardown()
    }

    func load(
        outgoingSong: Song,
        incomingSong: Song,
        startOffsetSeconds: TimeInterval,
        windowDuration: TimeInterval
    ) async {
        loadGeneration += 1
        let generation = loadGeneration

        stopPlayback()
        isLoaded = false
        loadError = nil

        let outgoingSnapshot = PlaybackCoordinator.makeWaveformSnapshot(for: outgoingSong)
        let incomingSnapshot = PlaybackCoordinator.makeWaveformSnapshot(for: incomingSong)
        guard let outgoingSnapshot, incomingSnapshot != nil else {
            loadError = "Unable to load song waveforms."
            return
        }

        guard generation == loadGeneration else { return }

        let outgoingDuration = outgoingSnapshot.timelineDuration
        let clampedOffset = OverlapTransitionTiming.clampedStartOffset(
            startOffsetSeconds,
            windowDuration: windowDuration,
            outgoingDuration: outgoingDuration
        )

        let outgoingWindowStart = max(0, outgoingDuration - windowDuration)
        let laneOffset = OverlapTransitionTiming.incomingLaneOffset(
            outgoingDuration: outgoingDuration,
            windowDuration: windowDuration,
            startOffsetSeconds: clampedOffset
        )

        previewStartTime = outgoingWindowStart
        incomingLaneOffset = laneOffset
        previewDuration = windowDuration

        do {
            try loadSong(outgoingSong, into: outgoingEngine)
            guard generation == loadGeneration else { return }
            try loadSong(incomingSong, into: incomingEngine)
            guard generation == loadGeneration else { return }

            outgoingEngine.setSuppressAutoStopOnPlaybackFinished(true)
            incomingEngine.setSuppressAutoStopOnPlaybackFinished(true)
            outgoingEngine.setMasterVolume(1)
            incomingEngine.setMasterVolume(1)

            isLoaded = true
        } catch {
            teardownEngines()
            loadError = error.localizedDescription
        }
    }

    func invalidateConfiguration() {
        loadGeneration += 1
        stopPlayback()
        isLoaded = false
    }

    func play() {
        guard isLoaded, !isPlaying else { return }

        outgoingEngine.seek(to: previewStartTime)
        incomingEngine.seek(to: 0)
        incomingEngine.setMasterVolume(0)
        incomingStarted = false

        outgoingEngine.play()
        guard outgoingEngine.isPlaying else {
            loadError = "Unable to start overlap preview."
            return
        }

        isPlaying = true
        currentTime = 0
        startTimer()
        // Incoming may need to start immediately when the overlap begins at the window start.
        syncIncomingAudibility()
    }

    func pause() {
        guard isPlaying else { return }
        refreshCurrentTime()
        outgoingEngine.pause()
        incomingEngine.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        stopPlayback()
    }

    func teardown() {
        stopPlayback()
        teardownEngines()
        isLoaded = false
    }

    private func loadSong(_ song: Song, into engine: AudioEngineManager) throws {
        let payloads = try SongTrackLoader.playbackPayloads(for: song)
        try engine.loadPreparedTracks(payloads)

        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        engine.setArrangement(SongPlaybackLayout(timeline: projectState.timeline))
        engine.setTempoMap(
            projectState.tempoChanges,
            timeSignatureChanges: projectState.timeSignatureChanges
        )
    }

    private func stopPlayback() {
        outgoingEngine.pause()
        incomingEngine.pause()
        outgoingEngine.seek(to: 0)
        incomingEngine.seek(to: 0)
        incomingEngine.setMasterVolume(1)
        isPlaying = false
        currentTime = 0
        incomingStarted = false
        stopTimer()
    }

    private func teardownEngines() {
        outgoingEngine.stop()
        incomingEngine.stop()
        outgoingEngine.suspendHardware()
        incomingEngine.suspendHardware()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.refreshCurrentTime()
            self.syncIncomingAudibility()

            if self.currentTime >= self.previewDuration - (1.0 / 48_000) {
                self.pause()
                self.currentTime = self.previewDuration
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func refreshCurrentTime() {
        let timeline = outgoingEngine.livePlayheadTime()
        currentTime = max(0, min(timeline - previewStartTime, previewDuration))
    }

    private func syncIncomingAudibility() {
        guard !incomingStarted, currentTime >= incomingLaneOffset - (1.0 / 48_000) else { return }

        incomingEngine.seek(to: 0)
        incomingEngine.setMasterVolume(1)
        if !incomingEngine.isPlaying {
            incomingEngine.play()
        }
        incomingStarted = true
    }
}
