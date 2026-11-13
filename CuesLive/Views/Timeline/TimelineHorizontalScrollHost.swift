#if os(macOS)
import AppKit
import SwiftUI

/// AppKit scroll view that owns the editor's horizontal axis on macOS.
///
/// The lanes are the document view, so a scroll tick is a clip-view bounds change and
/// nothing in SwiftUI is laid out. Only `onScroll` runs per tick, feeding the offset to the
/// rulers and the painted range. Wheel events the view cannot use, such as vertical ones,
/// fall through to the enclosing vertical scroll view as they would with a nested `ScrollView`.
struct TimelineHorizontalScrollHost<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    /// Drawn behind the scrolling content, at the viewport's size.
    let canvas: TimelineLaneCanvas
    let onScroll: (CGFloat) -> Void
    /// Command- or Option-scroll, with the factor to multiply the zoom by.
    let onWheelZoom: (CGFloat) -> Void
    /// Any press inside the lanes. Used to give keyboard focus back to the timeline.
    let onPointerDown: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> TimelineHorizontalNSScrollView<Content> {
        let view = TimelineHorizontalNSScrollView(rootView: content())
        view.onScroll = onScroll
        view.onWheelZoom = onWheelZoom
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ view: TimelineHorizontalNSScrollView<Content>, context: Context) {
        view.onScroll = onScroll
        view.onWheelZoom = onWheelZoom
        view.onPointerDown = onPointerDown
        view.update(rootView: content(), contentWidth: contentWidth, contentHeight: contentHeight)
        view.canvasView.update(canvas.scene(in: context.environment))
    }
}

final class TimelineHorizontalNSScrollView<Content: View>: NSScrollView {
    var onScroll: ((CGFloat) -> Void)?
    var onWheelZoom: ((CGFloat) -> Void)?
    var onPointerDown: (() -> Void)? {
        didSet { hostingView.onPointerDown = onPointerDown }
    }

    /// Sits below the clip view and does not scroll. It is redrawn at the new offset in the
    /// same event that moves the content, so the waveforms never lag the clip chrome.
    let canvasView = TimelineLaneCanvasView(frame: .zero)
    private let hostingView: TimelinePointerHostingView<Content>
    private var boundsObserver: NSObjectProtocol?
    /// The point under the pointer when a wheel zoom began, as a fraction of the content
    /// width and an x in the viewport. The next resize scrolls it back under the pointer.
    private var zoomAnchor: (fraction: CGFloat, viewportX: CGFloat)?

    init(rootView: Content) {
        hostingView = TimelinePointerHostingView(rootView: rootView)
        super.init(frame: .zero)
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        hostingView.sizingOptions = []
        documentView = hostingView
        addSubview(canvasView, positioned: .below, relativeTo: contentView)
        contentView.postsBoundsChangedNotifications = true
        // A generic class cannot expose a selector, so observe with a block.
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: nil
        ) { [weak self] _ in
            self?.clipViewBoundsDidChange()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func update(rootView: Content, contentWidth: CGFloat, contentHeight: CGFloat) {
        hostingView.rootView = rootView
        let size = NSSize(width: max(0, contentWidth), height: max(0, contentHeight))
        let oldWidth = hostingView.frame.width
        if hostingView.frame.size != size {
            hostingView.setFrameSize(size)
        }
        // The zoom lands in the first update after the wheel event. If it was clamped and
        // the width did not change, the anchor is dropped so a later resize cannot use it.
        if let zoomAnchor, size.width != oldWidth {
            let target = zoomAnchor.fraction * size.width - zoomAnchor.viewportX
            let maxOffset = max(0, size.width - contentView.bounds.width)
            contentView.scroll(to: NSPoint(x: min(max(0, target), maxOffset), y: contentView.bounds.origin.y))
            reflectScrolledClipView(contentView)
        }
        zoomAnchor = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let onWheelZoom, let scale = ScrollWheelZoom.scale(for: event) else {
            super.scrollWheel(with: event)
            return
        }
        let width = hostingView.frame.width
        guard width > 0, scale != 1 else { return }
        let viewportX = contentView.convert(event.locationInWindow, from: nil).x - contentView.bounds.origin.x
        zoomAnchor = ((contentView.bounds.origin.x + viewportX) / width, viewportX)
        onWheelZoom(scale)
    }

    override func tile() {
        super.tile()
        canvasView.frame = contentView.frame
    }

    private func clipViewBoundsDidChange() {
        let offset = contentView.bounds.origin.x
        canvasView.timelineOffsetDidChange(offset)
        onScroll?(offset)
    }
}

/// Hosting view that reports presses and leaves keyboard focus with the SwiftUI editor.
private final class TimelinePointerHostingView<Content: View>: NSHostingView<Content> {
    var onPointerDown: (() -> Void)?

    // The editor root holds focus for the clip shortcuts. Taking first responder here
    // on click would silently drop those key presses.
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        super.mouseDown(with: event)
    }
}
#endif
