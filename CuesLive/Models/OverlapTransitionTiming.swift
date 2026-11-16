import Foundation

/// Placement math for the overlap editor. `outgoingDuration` is where the outgoing song stops (its
/// out point) and `outgoingStart` its in point, both on its timeline; the overlap never reaches
/// back before the in point.
enum OverlapTransitionTiming {
    static let defaultEditorWindowDuration: TimeInterval = 10
    static let defaultStartOffsetSeconds: TimeInterval = 5

    static func defaultStartOffset(
        windowDuration: TimeInterval,
        outgoingDuration: TimeInterval,
        outgoingStart: TimeInterval = 0
    ) -> TimeInterval {
        guard windowDuration > 0 else { return 0 }
        return max(0, min(defaultStartOffsetSeconds, windowDuration, outgoingDuration - outgoingStart))
    }

    static func clampedStartOffset(
        _ offset: TimeInterval,
        windowDuration: TimeInterval,
        outgoingDuration: TimeInterval,
        outgoingStart: TimeInterval = 0
    ) -> TimeInterval {
        max(0, min(offset, min(windowDuration, outgoingDuration - outgoingStart)))
    }

    /// Where the editor window begins on the outgoing song: one window before its out point,
    /// but never before its in point.
    static func outgoingWindowStart(
        outgoingDuration: TimeInterval,
        windowDuration: TimeInterval,
        outgoingStart: TimeInterval = 0
    ) -> TimeInterval {
        max(outgoingStart, outgoingDuration - windowDuration)
    }

    /// Timeline position on the outgoing song where incoming playback begins.
    static func incomingAlignmentTime(
        outgoingDuration: TimeInterval,
        startOffsetSeconds: TimeInterval,
        outgoingStart: TimeInterval = 0
    ) -> TimeInterval {
        max(outgoingStart, outgoingDuration - startOffsetSeconds)
    }

    /// Offset of the incoming lane in the shared editor window (seconds).
    static func incomingLaneOffset(
        outgoingDuration: TimeInterval,
        windowDuration: TimeInterval,
        startOffsetSeconds: TimeInterval,
        outgoingStart: TimeInterval = 0
    ) -> TimeInterval {
        let windowStart = outgoingWindowStart(
            outgoingDuration: outgoingDuration,
            windowDuration: windowDuration,
            outgoingStart: outgoingStart
        )
        let alignmentTime = incomingAlignmentTime(
            outgoingDuration: outgoingDuration,
            startOffsetSeconds: startOffsetSeconds,
            outgoingStart: outgoingStart
        )
        return max(0, alignmentTime - windowStart)
    }

    static func startOffset(
        outgoingDuration: TimeInterval,
        windowDuration: TimeInterval,
        incomingLaneOffset: TimeInterval,
        outgoingStart: TimeInterval = 0
    ) -> TimeInterval {
        let windowStart = outgoingWindowStart(
            outgoingDuration: outgoingDuration,
            windowDuration: windowDuration,
            outgoingStart: outgoingStart
        )
        return clampedStartOffset(
            outgoingDuration - (windowStart + incomingLaneOffset),
            windowDuration: windowDuration,
            outgoingDuration: outgoingDuration,
            outgoingStart: outgoingStart
        )
    }
}
