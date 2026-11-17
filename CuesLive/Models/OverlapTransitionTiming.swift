import Foundation

/// Defaults for the overlap editor. `outgoingDuration` is where the outgoing song stops (its out
/// point) and `outgoingStart` its in point, both on its timeline.
enum OverlapTransitionTiming {
    /// Seconds the overlap editor shows across its width before zooming.
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
}
