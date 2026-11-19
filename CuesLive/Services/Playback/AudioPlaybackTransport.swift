import Foundation

/// Sample-accurate shared transport clock used by all track source nodes.
final class AudioPlaybackTransport: @unchecked Sendable {
    struct PendingTransition: Sendable, Equatable {
        let transitionAt: TimeInterval
        let targetOffset: TimeInterval
    }

    struct LoopRegion: Sendable, Equatable {
        let start: TimeInterval
        let end: TimeInterval

        var length: TimeInterval { end - start }
        var isValid: Bool { end > start }
    }

    /// A scheduled transition that falls inside the block being rendered.
    struct TransitionSplit: Sendable, Equatable {
        /// Timeline seconds from the start of the block to the transition point.
        let secondsUntil: TimeInterval
        /// Timeline position the block continues from after the transition point.
        let targetOffset: TimeInterval
    }

    struct RenderState: Sendable {
        let timelineSeconds: TimeInterval
        let isPlaying: Bool
        /// Set when a scheduled transition has not fired yet as of the block start, so
        /// the renderer can switch to the target mid-block instead of at the next block.
        var transitionSplit: TransitionSplit?
    }

    /// Read by every track's render block and written by the UI, the MIDI queue, and the
    /// render thread itself (anchor capture, scheduled jumps). Lock-free so the render
    /// thread never waits on another thread.
    private let clock = RealtimeSnapshot(TransportClock())

    var isPlaying: Bool { clock.load().isPlaying }
    var duration: TimeInterval { clock.load().duration }

    /// Sets the frame grid loop bounds snap to. Re-snaps an armed loop to the new grid.
    func setSampleRate(_ sampleRate: Double) {
        guard sampleRate > 0 else { return }
        let loop = clock.load().loopRegion
        clock.update { $0.sampleRate = sampleRate }
        if let loop {
            setLoopRegion(start: loop.start, end: loop.end)
        }
    }

    func setDuration(_ duration: TimeInterval) {
        clock.update { $0.duration = max(0, duration) }
    }

    func setPausedTimeline(_ timeline: TimeInterval) {
        clock.update { $0.pausedTimeline = max(0, min(timeline, $0.duration)) }
    }

    func pausedTimelineSeconds() -> TimeInterval {
        clock.load().pausedTimeline
    }

    func beginPlayback(from timeline: TimeInterval) {
        clock.update { state in
            state.pausedTimeline = max(0, min(timeline, state.duration))
            state.anchorTimeline = state.pausedTimeline
            state.hasAnchor = false
            state.isPlaying = true
        }
    }

    func pause(capturingTimeline timeline: TimeInterval) {
        clock.update { state in
            state.pausedTimeline = max(0, min(timeline, state.duration))
            state.isPlaying = false
            state.hasAnchor = false
        }
    }

    func stop() {
        clock.update { state in
            state.pausedTimeline = 0
            state.anchorTimeline = 0
            state.isPlaying = false
            state.hasAnchor = false
            state.pendingTransition = nil
        }
    }

    func scheduleTransition(to targetOffset: TimeInterval, at transitionTimelineTime: TimeInterval) {
        clock.update { state in
            state.pendingTransition = PendingTransition(
                transitionAt: max(0, min(transitionTimelineTime, state.duration)),
                targetOffset: max(0, min(targetOffset, state.duration))
            )
        }
    }

    func cancelScheduledTransition() {
        clock.update { $0.pendingTransition = nil }
    }

    /// True from scheduling until the audio thread has taken the jump (or it is cancelled).
    var hasPendingTransition: Bool {
        clock.load().pendingTransition != nil
    }

    func clearScheduledTransition() {
        clock.update { $0.pendingTransition = nil }
    }

    /// Enables sample-accurate section looping on the audio thread.
    /// Loop bounds are quantized to whole sample frames at the mixer's rate (`setSampleRate`).
    func setLoopRegion(start: TimeInterval, end: TimeInterval) {
        clock.update { state in
            let sampleRate = state.sampleRate
            let startFrame = Self.frameIndex(for: max(0, start), sampleRate: sampleRate)
            let endFrame = Self.frameIndex(for: max(0, end), sampleRate: sampleRate)
            let maxFrame = Self.frameIndex(for: state.duration, sampleRate: sampleRate)
            let clampedStart = min(max(0, startFrame), maxFrame)
            let clampedEnd = min(max(0, endFrame), maxFrame)
            if clampedEnd > clampedStart {
                state.loopRegion = LoopRegion(
                    start: Double(clampedStart) / sampleRate,
                    end: Double(clampedEnd) / sampleRate
                )
            } else {
                state.loopRegion = nil
            }
        }
    }

    /// Disarms the loop region.
    ///
    /// When `continuingFrom` is provided (the audible/wrapped playhead), the
    /// transport clock is re-anchored there in the same update so clearing a
    /// loop never briefly exposes the unwrapped timeline.
    ///
    /// Pass `hostTime` from the same clock the UI reads (`lastRenderTime`) and
    /// keep `hasAnchor == true` so a later audio callback does not capture a
    /// newer anchor that would make stale UI host times underflow.
    func clearLoopRegion(
        continuingFrom audibleTimeline: TimeInterval? = nil,
        hostTime: UInt64? = nil
    ) {
        clock.update { state in
            let hadActiveLoop = state.loopRegion?.isValid == true
            state.loopRegion = nil
            guard hadActiveLoop, let audibleTimeline else { return }
            let clamped = max(0, min(audibleTimeline, state.duration))
            state.pausedTimeline = clamped
            guard state.isPlaying else { return }
            state.anchorTimeline = clamped
            if let hostTime {
                state.anchorHostTime = hostTime
                state.hasAnchor = true
            } else {
                // Next render captures a fresh host-time anchor at elapsed = 0.
                state.hasAnchor = false
            }
        }
    }

    var hasActiveLoopRegion: Bool {
        clock.load().loopRegion?.isValid == true
    }

    func currentLoopRegion() -> LoopRegion? {
        clock.load().loopRegion
    }

    /// The timeline position each track source node renders from. With `captureAnchor`
    /// (the audio thread's read) this also pins the start anchor and takes due jumps.
    func renderTimeline(atHostTime hostTime: UInt64, captureAnchor: Bool) -> RenderState {
        guard captureAnchor else {
            var reading = clock.load()
            return reading.render(atHostTime: hostTime, captureAnchor: false)
        }
        return clock.update { $0.render(atHostTime: hostTime, captureAnchor: true) }
    }

    func timelineSeconds(atHostTime hostTime: UInt64) -> TimeInterval {
        renderTimeline(atHostTime: hostTime, captureAnchor: false).timelineSeconds
    }

    /// Playhead time for UI: wraps into the active loop from the same snapshot as the
    /// raw transport read so clearing a loop cannot tear the two apart.
    func audibleTimelineSeconds(atHostTime hostTime: UInt64?) -> TimeInterval {
        clock.load().audibleTimeline(atHostTime: hostTime)
    }

    func mappedTimeline(fromLinear linear: TimeInterval) -> TimeInterval {
        clock.load().mappedTimeline(fromLinear: linear)
    }

    func resetAnchor(to timeline: TimeInterval, hostTime: UInt64) {
        clock.update { state in
            state.anchorTimeline = max(0, min(timeline, state.duration))
            state.pausedTimeline = state.anchorTimeline
            state.anchorHostTime = hostTime
            state.hasAnchor = true
        }
    }

    /// Converts timeline seconds to a sample frame using floor so times in
    /// `[n/sr, (n+1)/sr)` always map to frame `n` (avoids cutting loop-start attacks).
    static func frameIndex(for time: TimeInterval, sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return 0 }
        let frames = time * sampleRate
        // Tiny epsilon keeps exact frame boundaries from drifting down a sample
        // due to floating-point representation of n/sampleRate.
        return Int((frames + 1e-9).rounded(.down))
    }

    /// Converts a region length in seconds to whole sample frames.
    ///
    /// Region lengths are produced by timeline subtraction (`sectionEnd - master`),
    /// which loses sub-sample precision, so a plain floor drops the final frame of
    /// a region. The tolerance is far below one sample but well above the
    /// accumulated double error for any realistic song length.
    static func frameSpan(forSeconds seconds: TimeInterval, sampleRate: Double) -> Int {
        guard seconds > 0, sampleRate > 0 else { return 0 }
        return max(0, Int((seconds * sampleRate + 1e-6).rounded(.down)))
    }

    /// Wraps `time` into `[start, end)` on whole sample frames.
    static func wrappedTimeline(
        _ time: TimeInterval,
        loop: LoopRegion,
        sampleRate: Double = DecodedStemBuffer.engineSampleRate
    ) -> TimeInterval {
        guard loop.isValid, sampleRate > 0 else { return time }
        let startFrame = frameIndex(for: loop.start, sampleRate: sampleRate)
        let endFrame = frameIndex(for: loop.end, sampleRate: sampleRate)
        let length = endFrame - startFrame
        guard length > 0 else { return time }

        let frame = frameIndex(for: time, sampleRate: sampleRate)
        if frame < startFrame {
            return time
        }
        guard frame >= endFrame else {
            // Keep continuous time inside the loop; only quantize when wrapping.
            return time
        }
        let wrappedFrame = startFrame + ((frame - startFrame) % length)
        return Double(wrappedFrame) / sampleRate
    }
}
