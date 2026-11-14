import SwiftUI

/// The fade handles on one clip. Dragging a length handle along the clip sets how long the fade
/// at that end lasts; dragging a curve handle up or down bends the fade.
struct ClipFadeHandles: View {
    private enum Handle: Equatable {
        case length(ClipEditing.Edge)
        case curve(ClipEditing.Edge)
    }

    private static let coordinateSpace = "clipFadeHandles"
    private static let knobSize: CGFloat = 7

    let clip: TrackClip
    let clipWidth: CGFloat
    let clipHeight: CGFloat
    /// The knobs are drawn only while this is set, or while one of them is being dragged.
    let showsKnobs: Bool
    /// The fade the drag asks for at that end. The editor previews it until the drag ends.
    let onDrag: (_ edge: ClipEditing.Edge, _ fade: ClipFade) -> Void
    let onEndDrag: () -> Void

    @State private var activeHandle: Handle?
    @State private var hoveredHandle: Handle?
    /// The fade as it was when a curve drag began.
    @State private var curveOrigin: ClipFade?

    private var layout: ClipFadeLayout {
        ClipFadeLayout(clip: clip, clipWidth: clipWidth, clipHeight: clipHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if layout.showsHandles {
                ForEach([ClipEditing.Edge.leading, .trailing], id: \.self) { edge in
                    knob(.length(edge), at: layout.lengthHandle(at: edge))
                        .highPriorityGesture(lengthDrag(at: edge))
                    if let center = layout.curveHandle(at: edge) {
                        knob(.curve(edge), at: center)
                            .highPriorityGesture(curveDrag(at: edge))
                    }
                }
            }
        }
        .frame(width: clipWidth, height: clipHeight, alignment: .topLeading)
        .coordinateSpace(name: Self.coordinateSpace)
    }

    private func knob(_ handle: Handle, at center: CGPoint) -> some View {
        let isVisible = showsKnobs || activeHandle != nil
        let isLit = hoveredHandle == handle || activeHandle == handle
        return Circle()
            .fill(Color.black.opacity(0.35))
            .overlay(Circle().strokeBorder(Color.white.opacity(isLit ? 0.9 : 0.78), lineWidth: 1))
            .frame(width: Self.knobSize, height: Self.knobSize)
            .opacity(isVisible ? 1 : 0)
            .frame(width: ClipFadeLayout.handleSize, height: ClipFadeLayout.handleSize)
            .contentShape(Rectangle())
            .onHover { isInside in
                if isInside {
                    hoveredHandle = handle
                } else if hoveredHandle == handle {
                    hoveredHandle = nil
                }
            }
            .offset(
                x: center.x - ClipFadeLayout.handleSize / 2,
                y: center.y - ClipFadeLayout.handleSize / 2
            )
    }

    private func lengthDrag(at edge: ClipEditing.Edge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                activeHandle = .length(edge)
                ClipPointerCursor.fadeLength.apply()
                onDrag(edge, ClipEditing.fade(clip, edge: edge, draggedTo: layout.time(atX: value.location.x)))
            }
            .onEnded { _ in endDrag() }
    }

    /// The middle of the curve follows the pointer: a body height of travel is the whole gain range.
    private func curveDrag(at edge: ClipEditing.Edge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                let origin = curveOrigin ?? layout.fade(at: edge)
                curveOrigin = origin
                activeHandle = .curve(edge)
                ClipPointerCursor.fadeCurve.apply()
                let gain = origin.gain(at: 0.5) - Double(value.translation.height / max(layout.bodyHeight, 1))
                onDrag(edge, origin.with(curvature: origin.curvature(forMidpointGain: gain)))
            }
            .onEnded { _ in endDrag() }
    }

    private func endDrag() {
        activeHandle = nil
        curveOrigin = nil
        ClipPointerCursor.reset()
        onEndDrag()
    }
}
