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

    private var timeline: OverlapEditorTimeline?
    /// Editor time where the running preview stops.
    private var previewEnd: TimeInterval = 0

    private(set) var isPlaying = false
    /// Editor time the preview has reached, on `OverlapEditorTimeline`'s axis. `nil` until it
    /// plays, and again once it is stopped or reconfigured.
    private(set) var playheadTime: TimeInterval?
    private(set) var isLoaded = false
    private(set) var loadError: String?

    deinit {
        teardown()
    }

    func load(
        outgoingSong: Song,
        incomingSong: Song,
        startOffsetSeconds: TimeInterval
    ) async {
        loadGeneration += 1
        let generation = loadGeneration

        stopPlayback()
        isLoaded = false
        loadError = nil

        let outgoingSnapshot = PlaybackCoordinator.makeWaveformSnapshot(for: outgoingSong)
        let incomingSnapshot = PlaybackCoordinator.makeWaveformSnapshot(for: incomingSong)
        guard let outgoingSnapshot, let incomingSnapshot else {
            loadError = "Unable to load song waveforms."
            return
        }

        guard generation == loadGeneration else { return }

        timeline = OverlapEditorTimeline(
            outgoingRange: outgoingSnapshot.window.start...outgoingSnapshot.window.end,
            incomingRange: incomingSnapshot.window.start...incomingSnapshot.window.end,
            startOffsetSeconds: startOffsetSeconds
        )

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

    /// Plays both songs from `editorTime` on the timeline until `endTime`: the outgoing song if
    /// it is still playing there, and the incoming song once it has entered.
    func play(from editorTime: TimeInterval, until endTime: TimeInterval) {
        guard isLoaded, !isPlaying, let timeline else { return }
        previewEnd = min(max(0, endTime), timeline.duration)
        let start = min(max(0, editorTime), previewEnd)

        incomingStarted = false
        incomingEngine.setMasterVolume(0)
        if let incomingTime = timeline.incomingTime(at: start) {
            incomingEngine.seek(to: incomingTime)
            incomingEngine.setMasterVolume(1)
            incomingEngine.play()
            incomingStarted = true
        } else {
            incomingEngine.seek(to: timeline.incomingRange.lowerBound)
        }
        if let outgoingTime = timeline.outgoingTime(at: start) {
            outgoingEngine.seek(to: outgoingTime)
            outgoingEngine.play()
        }

        guard outgoingEngine.isPlaying || incomingEngine.isPlaying else {
            loadError = "Unable to start overlap preview."
            return
        }

        isPlaying = true
        playheadTime = start
        startTimer()
        // Incoming may need to start immediately when the overlap begins at the preview start.
        syncIncomingAudibility()
    }

    /// Moves a running preview to `editorTime` and keeps playing. Does nothing while stopped.
    func seek(to editorTime: TimeInterval) {
        guard isPlaying else { return }
        outgoingEngine.pause()
        incomingEngine.pause()
        stopTimer()
        isPlaying = false
        play(from: editorTime, until: previewEnd)
    }

    func pause() {
        guard isPlaying else { return }
        refreshCurrentTime()
        outgoingEngine.pause()
        incomingEngine.pause()
        isPlaying = false
        stopTimer()
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
        outgoingEngine.seek(to: outgoingEngine.startTime)
        incomingEngine.seek(to: incomingEngine.startTime)
        incomingEngine.setMasterVolume(1)
        isPlaying = false
        playheadTime = nil
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

            if let playheadTime = self.playheadTime, playheadTime >= self.previewEnd - (1.0 / 48_000) {
                self.pause()
                self.playheadTime = self.previewEnd
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// Follows the outgoing song until it ends, then the incoming song.
    private func refreshCurrentTime() {
        guard let timeline else { return }
        let outgoingTime = outgoingEngine.livePlayheadTime()
        let time: TimeInterval
        if outgoingEngine.isPlaying, outgoingTime < timeline.outgoingRange.upperBound || !incomingStarted {
            time = timeline.editorTime(outgoingTime: outgoingTime)
        } else {
            time = timeline.editorTime(incomingTime: incomingEngine.livePlayheadTime())
        }
        playheadTime = min(max(0, time), timeline.duration)
    }

    private func syncIncomingAudibility() {
        guard !incomingStarted,
              let timeline,
              let playheadTime,
              playheadTime >= timeline.incomingEntry - (1.0 / 48_000) else { return }

        incomingEngine.seek(to: timeline.incomingRange.lowerBound)
        incomingEngine.setMasterVolume(1)
        if !incomingEngine.isPlaying {
            incomingEngine.play()
        }
        incomingStarted = true
    }
}
