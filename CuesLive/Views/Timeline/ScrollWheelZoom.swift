#if os(macOS)
import AppKit

/// Turns a Command- or Option-held scroll into a zoom factor, the way Logic, Pro Tools and
/// Ableton let a mouse zoom a timeline. Scrolling up (away from the user) zooms in.
enum ScrollWheelZoom {
    /// Zoom change per point of trackpad scroll.
    static let preciseSensitivity: CGFloat = 0.01
    /// Zoom change per mouse-wheel line, about 12% a notch.
    static let lineSensitivity: CGFloat = 0.12

    /// The factor to multiply the zoom by, or `nil` when the event should scroll instead.
    static func scale(for event: NSEvent) -> CGFloat? {
        scale(
            deltaY: event.scrollingDeltaY,
            hasPreciseDeltas: event.hasPreciseScrollingDeltas,
            modifiers: event.modifierFlags
        )
    }

    static func scale(
        deltaY: CGFloat,
        hasPreciseDeltas: Bool,
        modifiers: NSEvent.ModifierFlags
    ) -> CGFloat? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.option) else { return nil }
        let sensitivity = hasPreciseDeltas ? preciseSensitivity : lineSensitivity
        return exp(deltaY * sensitivity)
    }
}
#endif
