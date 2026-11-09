import Foundation

/// A spoken section callout the Smart Guide should play now.
struct SmartGuideCall: Equatable {
    let name: String
    /// Timeline position the callout leads into (section start, cue fire time, or loop end).
    let boundary: TimeInterval
}

/// Decides when Smart Guide speaks. Calls fire one measure before the boundary playback is heading to:
/// the next section, a queued section cue, or the wrap point of an active loop.
///
/// A call only fires when playback *crosses* the one-measure mark. Landing inside that final measure
/// (a late cue, a seek, a loop engaging near its end) stays silent rather than calling late.
struct SmartGuideCallPlanner {
    struct Cue: Equatable {
        let name: String
        let fireTime: TimeInterval
    }

    /// Forward steps larger than this are treated as seeks, not playback.
    static let maxContinuousStep: TimeInterval = 1.0
    /// Backward steps larger than this are treated as seeks or loop wraps.
    static let backwardJumpThreshold: TimeInterval = 0.05
    /// How close to a loop's start still counts as the start of a pass.
    static let loopStartTolerance: TimeInterval = 0.25

    private var lastTime: TimeInterval = 0
    private var armedBoundary: TimeInterval?
    private var calledBoundary: TimeInterval?

    mutating func reset(at time: TimeInterval = 0) {
        lastTime = time
        armedBoundary = nil
        calledBoundary = nil
    }

    /// - Parameters:
    ///   - sections: Display sections on the timeline.
    ///   - cue: Queued section cue, if any.
    ///   - loop: Section currently looping, if any. A loop takes precedence over a cue.
    ///   - leadDuration: Duration of one measure ending at the given timeline position.
    mutating func evaluate(
        at time: TimeInterval,
        sections: [SongSection],
        cue: Cue?,
        loop: SongSection?,
        leadDuration: (TimeInterval) -> TimeInterval
    ) -> SmartGuideCall? {
        defer { lastTime = time }

        if time + Self.backwardJumpThreshold < lastTime {
            // Seek back or loop wrap: the same boundary may call again.
            calledBoundary = nil
            armedBoundary = nil
        } else if time - lastTime > Self.maxContinuousStep {
            armedBoundary = nil
        }

        guard let target = target(at: time, sections: sections, cue: cue, loop: loop),
              time + 0.001 < target.boundary else {
            armedBoundary = nil
            return nil
        }

        if let armedBoundary, !Self.sameBoundary(armedBoundary, target.boundary) {
            self.armedBoundary = nil
        }

        let announceAt = max(0, target.boundary - leadDuration(target.boundary))

        if time < announceAt || Self.isAtPassStart(time: time, target: target, announceAt: announceAt) {
            armedBoundary = target.boundary
        }

        guard time >= announceAt,
              let armedBoundary,
              Self.sameBoundary(armedBoundary, target.boundary) else {
            return nil
        }
        if let calledBoundary, Self.sameBoundary(calledBoundary, target.boundary) {
            return nil
        }

        calledBoundary = target.boundary
        return SmartGuideCall(name: target.name, boundary: target.boundary)
    }

    // MARK: - Private

    private struct Target {
        let name: String
        let boundary: TimeInterval
        /// Start of the looping section, when the target is a loop wrap point.
        let loopStart: TimeInterval?
    }

    private func target(
        at time: TimeInterval,
        sections: [SongSection],
        cue: Cue?,
        loop: SongSection?
    ) -> Target? {
        if let loop {
            return Target(
                name: loop.name,
                boundary: loop.timelineEndSeconds,
                loopStart: loop.timelineStartSeconds
            )
        }

        if let cue, cue.fireTime > time + 0.001 {
            return Target(name: cue.name, boundary: cue.fireTime, loopStart: nil)
        }

        let upcoming = sections
            .filter { $0.timelineStartSeconds > time + 0.001 }
            .min { $0.timelineStartSeconds < $1.timelineStartSeconds }
        guard let upcoming else { return nil }
        return Target(name: upcoming.name, boundary: upcoming.timelineStartSeconds, loopStart: nil)
    }

    /// Short loops (or sections shorter than a measure) have no room before the lead point, so the
    /// start of a pass counts as being armed. The same applies to a first boundary inside the opening measure.
    private static func isAtPassStart(time: TimeInterval, target: Target, announceAt: TimeInterval) -> Bool {
        if let loopStart = target.loopStart {
            return time >= loopStart - 0.05 && time <= loopStart + loopStartTolerance
        }
        return announceAt <= 0 && time <= backwardJumpThreshold
    }

    private static func sameBoundary(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        abs(lhs - rhs) < 0.001
    }
}
