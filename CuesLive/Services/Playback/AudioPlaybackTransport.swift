import AVFoundation
import Foundation
import os

/// Sample-accurate shared transport clock used by all track source nodes.
final class AudioPlaybackTransport: @unchecked Sendable {
    struct PendingTransition: Sendable {
        let transitionAt: TimeInterval
        let targetOffset: TimeInterval
    }

    struct LoopRegion: Sendable, Equatable {
        let start: TimeInterval
        let end: TimeInterval

        var length: TimeInterval { end - start }
        var isValid: Bool { end > start }
    }

    struct RenderState: Sendable {
        let timelineSeconds: TimeInterval
        let isPlaying: Bool
        let playbackRatio: Double
    }

    private var lock = os_unfair_lock()
    private static var hostTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0

    private var pausedTimeline: TimeInterval = 0
    private var anchorTimeline: TimeInterval = 0
    private var anchorHostTime: UInt64 = 0
    private var hasAnchor = false
    private var pendingTransition: PendingTransition?
    private var loopRegion: LoopRegion?
    private var tempoPlaybackMap = TempoPlaybackMap(segments: [])
    private var usesTempoMap = false

    func setDuration(_ duration: TimeInterval) {
        os_unfair_lock_lock(&lock)
        self.duration = max(0, duration)
        os_unfair_lock_unlock(&lock)
    }

    func setPausedTimeline(_ timeline: TimeInterval) {
        os_unfair_lock_lock(&lock)
        pausedTimeline = max(0, min(timeline, duration))
        os_unfair_lock_unlock(&lock)
    }

    func pausedTimelineSeconds() -> TimeInterval {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return pausedTimeline
    }

    func beginPlayback(from timeline: TimeInterval) {
        os_unfair_lock_lock(&lock)
        pausedTimeline = max(0, min(timeline, duration))
        anchorTimeline = pausedTimeline
        hasAnchor = false
        isPlaying = true
        os_unfair_lock_unlock(&lock)
    }

    func pause(capturingTimeline timeline: TimeInterval) {
        os_unfair_lock_lock(&lock)
        pausedTimeline = max(0, min(timeline, duration))
        isPlaying = false
        hasAnchor = false
        os_unfair_lock_unlock(&lock)
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        pausedTimeline = 0
        anchorTimeline = 0
        isPlaying = false
        hasAnchor = false
        pendingTransition = nil
        os_unfair_lock_unlock(&lock)
    }

    func scheduleTransition(to targetOffset: TimeInterval, at transitionTimelineTime: TimeInterval) {
        os_unfair_lock_lock(&lock)
        let target = max(0, min(targetOffset, duration))
        let transitionAt = max(0, min(transitionTimelineTime, duration))
        pendingTransition = PendingTransition(transitionAt: transitionAt, targetOffset: target)
        os_unfair_lock_unlock(&lock)
    }

    func cancelScheduledTransition() {
        os_unfair_lock_lock(&lock)
        pendingTransition = nil
        os_unfair_lock_unlock(&lock)
    }

    func setTempoMap(
        changes: [TempoChange],
        referenceBPM: Double,
        timeSignatureChanges: [TimeSignatureChange],
        duration: TimeInterval
    ) {
        os_unfair_lock_lock(&lock)
        // Extend well past song duration so unwrapped loop timelines can keep
        // advancing. Using `duration` here previously froze the playhead at the
        // song end, which modulo-mapped to frame 0 forever while looping.
        tempoPlaybackMap = TempoPlaybackMap.build(
            tempoChanges: changes.sortedByMeasure,
            referenceBPM: referenceBPM,
            timeSignatureChanges: timeSignatureChanges,
            maxSourceTime: max(duration, TempoPlaybackMap.defaultMaxSourceTime)
        )
        usesTempoMap = referenceBPM > 0 && !changes.isEmpty
        os_unfair_lock_unlock(&lock)
    }

    func clearScheduledTransition() {
        os_unfair_lock_lock(&lock)
        pendingTransition = nil
        os_unfair_lock_unlock(&lock)
    }

    /// Enables sample-accurate section looping on the audio thread.
    /// Loop bounds are quantized to whole sample frames at the engine sample rate.
    func setLoopRegion(start: TimeInterval, end: TimeInterval) {
        os_unfair_lock_lock(&lock)
        let sampleRate = DecodedStemBuffer.engineSampleRate
        let startFrame = Self.frameIndex(for: max(0, start), sampleRate: sampleRate)
        let endFrame = Self.frameIndex(for: max(0, end), sampleRate: sampleRate)
        let maxFrame = Self.frameIndex(for: duration, sampleRate: sampleRate)
        let clampedStart = min(max(0, startFrame), maxFrame)
        let clampedEnd = min(max(0, endFrame), maxFrame)
        if clampedEnd > clampedStart {
            loopRegion = LoopRegion(
                start: Double(clampedStart) / sampleRate,
                end: Double(clampedEnd) / sampleRate
            )
        } else {
            loopRegion = nil
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Disarms the loop region.
    ///
    /// When `continuingFrom` is provided (the audible/wrapped playhead), the
    /// transport clock is re-anchored there under the same lock so clearing a
    /// loop never briefly exposes the unwrapped timeline.
    ///
    /// Pass `hostTime` from the same clock the UI reads (`lastRenderTime`) and
    /// keep `hasAnchor == true` so a later audio callback does not capture a
    /// newer anchor that would make stale UI host times underflow.
    func clearLoopRegion(
        continuingFrom audibleTimeline: TimeInterval? = nil,
        hostTime: UInt64? = nil
    ) {
        os_unfair_lock_lock(&lock)
        let hadActiveLoop = loopRegion?.isValid == true
        loopRegion = nil
        if hadActiveLoop, let audibleTimeline {
            let clamped = max(0, min(audibleTimeline, duration))
            pausedTimeline = clamped
            if isPlaying {
                anchorTimeline = clamped
                if let hostTime {
                    anchorHostTime = hostTime
                    hasAnchor = true
                } else {
                    // Next render captures a fresh host-time anchor at elapsed = 0.
                    hasAnchor = false
                }
            }
        }
        os_unfair_lock_unlock(&lock)
    }

    var hasActiveLoopRegion: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return loopRegion?.isValid == true
    }

    func currentLoopRegion() -> LoopRegion? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return loopRegion
    }

    /// Single locked read used by each track source node.
    func renderTimeline(atHostTime hostTime: UInt64, captureAnchor: Bool) -> RenderState {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return renderTimelineLocked(atHostTime: hostTime, captureAnchor: captureAnchor)
    }

    func timelineSeconds(atHostTime hostTime: UInt64) -> TimeInterval {
        renderTimeline(atHostTime: hostTime, captureAnchor: false).timelineSeconds
    }

    /// Playhead time for UI: wraps into the active loop under the same lock as the
    /// raw transport read so clearing a loop cannot tear the two apart.
    func audibleTimelineSeconds(atHostTime hostTime: UInt64?) -> TimeInterval {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let raw: TimeInterval
        if let hostTime {
            raw = renderTimelineLocked(atHostTime: hostTime, captureAnchor: false).timelineSeconds
        } else {
            raw = pausedTimeline
        }
        if let loopRegion, loopRegion.isValid {
            return Self.wrappedTimeline(raw, loop: loopRegion)
        }
        return raw
    }

    /// Must be called while `lock` is held.
    private func renderTimelineLocked(atHostTime hostTime: UInt64, captureAnchor: Bool) -> RenderState {
        if captureAnchor, isPlaying, !hasAnchor {
            anchorHostTime = hostTime
            hasAnchor = true
        }

        guard isPlaying else {
            return RenderState(timelineSeconds: pausedTimeline, isPlaying: false, playbackRatio: 1.0)
        }

        guard hasAnchor else {
            return RenderState(timelineSeconds: pausedTimeline, isPlaying: true, playbackRatio: 1.0)
        }

        // UI may read `outputNode.lastRenderTime` behind a freshly captured audio
        // anchor; unsigned subtraction would underflow and flash the playhead ahead.
        guard hostTime >= anchorHostTime else {
            let anchored = positionedTimeline(anchorTimeline)
            let ratio = usesTempoMap ? tempoPlaybackMap.ratio(at: anchored) : 1.0
            return RenderState(timelineSeconds: anchored, isPlaying: true, playbackRatio: ratio)
        }

        let elapsed = Self.seconds(fromHostTimeDelta: hostTime &- anchorHostTime)
        let timeline: TimeInterval
        if usesTempoMap {
            timeline = tempoPlaybackMap.sourceTimeAfterWallElapsed(
                from: anchorTimeline,
                wallElapsed: elapsed
            )
        } else {
            timeline = anchorTimeline + elapsed
        }
        let positioned = positionedTimeline(mappedTimeline(fromLinear: timeline))

        let ratio: Double
        if usesTempoMap {
            let ratioTime: TimeInterval
            if let loopRegion, loopRegion.isValid {
                ratioTime = Self.wrappedTimeline(positioned, loop: loopRegion)
            } else {
                ratioTime = positioned
            }
            ratio = tempoPlaybackMap.ratio(at: ratioTime)
        } else {
            ratio = 1.0
        }
        return RenderState(timelineSeconds: positioned, isPlaying: true, playbackRatio: ratio)
    }

    /// When a section loop is armed, keep continuous unwrapped time so the player
    /// can apply integer-frame modulo. Otherwise clamp to song duration.
    private func positionedTimeline(_ mapped: TimeInterval) -> TimeInterval {
        if loopRegion?.isValid == true {
            return max(0, mapped)
        }
        return max(0, min(mapped, duration))
    }

    func playbackRatio(at timeline: TimeInterval) -> Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard usesTempoMap else { return 1.0 }
        return tempoPlaybackMap.ratio(at: timeline)
    }

    func mappedTimeline(fromLinear linear: TimeInterval) -> TimeInterval {
        if let pendingTransition, linear >= pendingTransition.transitionAt {
            let jumped = pendingTransition.targetOffset + (linear - pendingTransition.transitionAt)
            return max(0, min(jumped, duration))
        }
        return linear
    }

    func resetAnchor(to timeline: TimeInterval, hostTime: UInt64) {
        os_unfair_lock_lock(&lock)
        anchorTimeline = max(0, min(timeline, duration))
        pausedTimeline = anchorTimeline
        anchorHostTime = hostTime
        hasAnchor = true
        os_unfair_lock_unlock(&lock)
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

    private static func seconds(fromHostTimeDelta delta: UInt64) -> TimeInterval {
        let nanos = Double(delta) * Double(hostTimebase.numer) / Double(hostTimebase.denom)
        return nanos / 1_000_000_000
    }
}
