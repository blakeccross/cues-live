import SwiftUI

/// Waveform loading and audible preview of the overlap.
extension SetlistOverlapEditorView {
    func loadWaveformSnapshotsIfNeeded() async {
        if outgoingSnapshot == nil || incomingSnapshot == nil {
            isLoadingWaveforms = true
            await Task.yield()
        }

        if outgoingSnapshot == nil {
            outgoingSnapshot = context.outgoingSnapshot
                ?? PlaybackCoordinator.makeWaveformSnapshot(for: context.outgoingSong)
        }
        if incomingSnapshot == nil {
            incomingSnapshot = context.incomingSnapshot
                ?? PlaybackCoordinator.makeWaveformSnapshot(for: context.incomingSong)
        }

        applyDefaultStartOffsetIfNeeded()
        updateFocusRange()
        seekTime = defaultSeekTime
        isLoadingWaveforms = false
        transitionCenterRequest += 1
    }

    private func applyDefaultStartOffsetIfNeeded() {
        guard context.initialStartOffset <= 0,
              startOffsetSeconds <= 0,
              let outgoingSnapshot else {
            return
        }

        startOffsetSeconds = OverlapTransitionTiming.defaultStartOffset(
            windowDuration: baseWindowDuration,
            outgoingDuration: outgoingSnapshot.timelineDuration,
            outgoingStart: outgoingSnapshot.startTime
        )
    }

    func invalidatePreviewConfiguration() {
        if previewEngine.isPlaying {
            previewEngine.pause()
            restoreLivePlaybackIfNeeded()
        }
        previewEngine.invalidateConfiguration()
    }

    func togglePreview() async {
        if previewEngine.isPlaying {
            previewEngine.pause()
            return
        }

        previewError = nil
        // Starting again from the end replays the transition.
        if seekTime >= focusRange.upperBound - Self.restartTolerance {
            seekTime = defaultSeekTime
        }
        pauseLivePlaybackForPreview()
        if !previewEngine.isLoaded {
            await loadPreview()
        }
        guard previewEngine.isLoaded else {
            previewError = previewEngine.loadError ?? "Unable to load overlap preview."
            restoreLivePlaybackIfNeeded()
            return
        }

        previewEngine.play(from: playheadPosition, until: focusRange.upperBound)
        previewError = previewEngine.loadError
        if previewEngine.loadError != nil || !previewEngine.isPlaying {
            if !previewEngine.isPlaying, previewError == nil {
                previewError = "Unable to start overlap preview."
            }
            restoreLivePlaybackIfNeeded()
        }
    }

    private func pauseLivePlaybackForPreview() {
        let audioEngine = AudioEngineManager.shared
        wasLivePlaybackRunning = audioEngine.isPlaying
        if wasLivePlaybackRunning {
            audioEngine.pause()
        }
        audioEngine.suspendHardware()
    }

    func restoreLivePlaybackIfNeeded() {
        AudioEngineManager.shared.resumeHardware()
        if wasLivePlaybackRunning {
            AudioEngineManager.shared.play()
            wasLivePlaybackRunning = false
        }
    }

    private func loadPreview() async {
        isLoadingPreview = true
        previewError = nil
        defer { isLoadingPreview = false }

        await previewEngine.load(
            outgoingSong: context.outgoingSong,
            incomingSong: context.incomingSong,
            startOffsetSeconds: startOffsetSeconds
        )
        previewError = previewEngine.loadError
    }
}
