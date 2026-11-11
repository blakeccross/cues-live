import SwiftUI

/// Modifier keys held at the moment of a pointer event. Always empty on iOS.
struct PointerModifiers: Equatable {
    var shift = false
    var command = false
    var option = false
    var control = false

    static var current: PointerModifiers {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        return PointerModifiers(
            shift: flags.contains(.shift),
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
        #else
        return PointerModifiers()
        #endif
    }
}

/// The pointer's job on a clip.
enum ClipPointerCursor: Equatable {
    case select
    case move
    case trim

    /// Trim handles own the header ends. The top half of the lane selects a range; the bottom half moves.
    static func zone(
        at location: CGPoint,
        clipWidth: CGFloat,
        laneHeight: CGFloat,
        headerHeight: CGFloat = TimelineLayout.clipHeaderHeight,
        edgeWidth: CGFloat = TimelineLayout.clipTrimHandleWidth
    ) -> ClipPointerCursor {
        let onHeaderEdge = location.y >= 0
            && location.y <= headerHeight
            && clipWidth >= edgeWidth * 2
            && (location.x <= edgeWidth || location.x >= clipWidth - edgeWidth)
        if onHeaderEdge {
            return .trim
        }
        if location.y < laneHeight / 2 {
            return .select
        }
        return .move
    }

    func apply() {
        #if os(macOS)
        switch self {
        case .select: NSCursor.iBeam.set()
        case .move: NSCursor.openHand.set()
        case .trim: NSCursor.resizeLeftRight.set()
        }
        #endif
    }

    static func reset() {
        #if os(macOS)
        NSCursor.arrow.set()
        #endif
    }
}

/// An in-progress drag on the clip selection, already snapped and clamped.
enum ClipDrag: Equatable {
    case move(delta: TimeInterval, copy: Bool)
    case trim(edge: ClipEditing.Edge, delta: TimeInterval)
}

/// A raw drag reported by a lane. `reference` is the clip under the pointer; the editor snaps
/// its position and applies the same change to every selected clip.
enum ClipDragRequest {
    case move(reference: TrackClip, rawDelta: TimeInterval, copy: Bool)
    case trim(reference: TrackClip, edge: ClipEditing.Edge, rawTime: TimeInterval)
}

enum ClipMenuAction {
    case split
    case duplicate
    case join
    case adjustGain
    case delete
}

/// What a lane reports back to the editor, which owns the clip selection.
struct ClipLaneActions {
    /// Pointer-down on a clip.
    var press: (_ clipID: UUID, _ trackID: UUID, _ modifiers: PointerModifiers) -> Void
    /// Pointer-up on a clip without a drag. `time` is the snapped pointer position.
    var click: (_ clipID: UUID, _ modifiers: PointerModifiers, _ time: TimeInterval) -> Void
    var drag: (ClipDragRequest) -> Void
    var endDrag: () -> Void
    /// Time-range drag across lanes, in `TimelineLayout.trackLanesCoordinateSpace`.
    var marquee: (_ start: CGPoint, _ current: CGPoint, _ modifiers: PointerModifiers) -> Void
    /// The pointer went up after a range drag. The edit selection stays.
    var endMarquee: () -> Void
    /// Click on blank lane space at a snapped timeline time.
    var clickBlank: (_ trackID: UUID, _ time: TimeInterval) -> Void
    /// Selector press. Places the insertion cursor on this track at the snapped beat.
    var locate: (_ trackID: UUID, _ time: TimeInterval) -> Void
    var menu: (_ action: ClipMenuAction, _ clipID: UUID) -> Void
}
