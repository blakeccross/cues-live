import Foundation

/// Everything `AudioPlaybackTransport` knows about the playhead, as one plain value so the
/// transport can publish it atomically to the audio thread.
struct TransportClock: Equatable {
    var isPlaying = false
    var duration: TimeInterval = 0
    var pausedTimeline: TimeInterval = 0
    var anchorTimeline: TimeInterval = 0
    var anchorHostTime: UInt64 = 0
    var hasAnchor = false
    var pendingTransition: AudioPlaybackTransport.PendingTransition?
    var loopRegion: AudioPlaybackTransport.LoopRegion?
    /// Read once at creation rather than from a lazy static, whose first access on the
    /// render thread would go through a one-time initialization lock.
    private let timebaseNumer: UInt32
    private let timebaseDenom: UInt32

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebaseNumer = info.numer
        timebaseDenom = info.denom
    }

    /// Timeline position at `hostTime`. With `captureAnchor`, this is the audio thread's
    /// read: it pins the start anchor on the first block after playback begins and takes a
    /// scheduled jump once the clock reaches it. Without it the clock is left untouched.
    mutating func render(atHostTime hostTime: UInt64, captureAnchor: Bool) -> AudioPlaybackTransport.RenderState {
        if captureAnchor, isPlaying, !hasAnchor {
            anchorHostTime = hostTime
            hasAnchor = true
        }

        guard isPlaying else {
            return AudioPlaybackTransport.RenderState(timelineSeconds: pausedTimeline, isPlaying: false)
        }

        guard hasAnchor else {
            return AudioPlaybackTransport.RenderState(timelineSeconds: pausedTimeline, isPlaying: true)
        }

        // UI may read `outputNode.lastRenderTime` behind a freshly captured audio
        // anchor; unsigned subtraction would underflow and flash the playhead ahead.
        guard hostTime >= anchorHostTime else {
            return AudioPlaybackTransport.RenderState(timelineSeconds: positionedTimeline(anchorTimeline), isPlaying: true)
        }

        var timeline = linearTimeline(atHostTime: hostTime)
        // The audio thread re-anchors the clock on the jump itself, at the host time the
        // transition point was reached. Every track then reads one continuous clock, and
        // nothing on the UI thread has to touch it (a UI re-anchor lands at an arbitrary
        // moment and splices audible glitches into the stream).
        if captureAnchor, loopRegion?.isValid != true,
           let pendingTransition, timeline >= pendingTransition.transitionAt {
            let wallToTransition = max(0, pendingTransition.transitionAt - anchorTimeline)
            anchorHostTime = anchorHostTime &+ hostTicks(forSeconds: wallToTransition)
            anchorTimeline = pendingTransition.targetOffset
            pausedTimeline = pendingTransition.targetOffset
            self.pendingTransition = nil
            timeline = linearTimeline(atHostTime: hostTime)
        }
        let positioned = positionedTimeline(mappedTimeline(fromLinear: timeline))
        var split: AudioPlaybackTransport.TransitionSplit?
        if let pendingTransition, loopRegion?.isValid != true, timeline < pendingTransition.transitionAt {
            split = AudioPlaybackTransport.TransitionSplit(
                secondsUntil: pendingTransition.transitionAt - timeline,
                targetOffset: pendingTransition.targetOffset
            )
        }
        return AudioPlaybackTransport.RenderState(timelineSeconds: positioned, isPlaying: true, transitionSplit: split)
    }

    /// Playhead time for UI, wrapped into the active loop.
    func audibleTimeline(atHostTime hostTime: UInt64?) -> TimeInterval {
        var reading = self
        let raw = hostTime.map { reading.render(atHostTime: $0, captureAnchor: false).timelineSeconds }
            ?? pausedTimeline
        if let loopRegion, loopRegion.isValid {
            return AudioPlaybackTransport.wrappedTimeline(raw, loop: loopRegion)
        }
        return raw
    }

    func mappedTimeline(fromLinear linear: TimeInterval) -> TimeInterval {
        if let pendingTransition, linear >= pendingTransition.transitionAt {
            let jumped = pendingTransition.targetOffset + (linear - pendingTransition.transitionAt)
            return max(0, min(jumped, duration))
        }
        return linear
    }

    private func linearTimeline(atHostTime hostTime: UInt64) -> TimeInterval {
        anchorTimeline + seconds(fromHostTimeDelta: hostTime &- anchorHostTime)
    }

    /// When a section loop is armed, keep continuous unwrapped time so the player
    /// can apply integer-frame modulo. Otherwise clamp to song duration.
    private func positionedTimeline(_ mapped: TimeInterval) -> TimeInterval {
        if loopRegion?.isValid == true {
            return max(0, mapped)
        }
        return max(0, min(mapped, duration))
    }

    private func hostTicks(forSeconds seconds: TimeInterval) -> UInt64 {
        guard seconds > 0 else { return 0 }
        return UInt64(seconds * 1_000_000_000 * Double(timebaseDenom) / Double(timebaseNumer))
    }

    private func seconds(fromHostTimeDelta delta: UInt64) -> TimeInterval {
        let nanos = Double(delta) * Double(timebaseNumer) / Double(timebaseDenom)
        return nanos / 1_000_000_000
    }
}
