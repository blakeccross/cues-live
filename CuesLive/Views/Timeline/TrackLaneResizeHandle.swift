import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Bottom edge of a track header. The drag distance is measured in screen space so the
/// lane can grow under the pointer without the gesture feeding on its own movement.
struct TrackLaneResizeHandle: View {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    var body: some View {
        #if os(macOS)
        TrackLaneResizeHandleMac(onChanged: onChanged, onEnded: onEnded)
        #else
        Color.clear
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        onChanged(value.translation.height)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
        #endif
    }
}

#if os(macOS)
private struct TrackLaneResizeHandleMac: NSViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> TrackLaneResizeHandleView {
        let view = TrackLaneResizeHandleView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: TrackLaneResizeHandleView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }
}

private final class TrackLaneResizeHandleView: NSView {
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?
    private var startY: CGFloat?
    private var dragged = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        startY = NSEvent.mouseLocation.y
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startY else { return }
        dragged = true
        onChanged?(startY - NSEvent.mouseLocation.y)
    }

    override func mouseUp(with event: NSEvent) {
        let didDrag = dragged
        startY = nil
        dragged = false
        if didDrag {
            onEnded?()
        }
    }
}
#endif
