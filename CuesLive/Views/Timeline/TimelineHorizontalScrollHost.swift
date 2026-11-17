#if os(macOS)
import AppKit
import SwiftUI

/// AppKit scroll view that owns the editor's horizontal axis on macOS.
///
/// The lanes are the document view, so a scroll tick is a clip-view bounds change and
/// nothing in SwiftUI is laid out. Only `onScroll` runs per tick, feeding the offset to the
/// rulers and the painted range. Wheel events the view cannot use, such as vertical ones,
/// fall through to the enclosing vertical scroll view as they would with a nested `ScrollView`.
///
/// A pinch or Command-scroll zooms live, one step per display refresh: the lane canvas, the
/// grid and the live ruler redraw at the new zoom, and the SwiftUI lane chrome is stretched to
/// match. The editor's zoom is set once, when a pinch ends or a wheel zoom goes still, so
/// SwiftUI lays the editor out once.
struct TimelineHorizontalScrollHost<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    /// The editor's zoom. When it changes, the content under the zoom's anchor stays put.
    let zoom: CGFloat
    let zoomRange: ClosedRange<CGFloat>
    /// Drawn behind the scrolling content, at the viewport's size.
    let canvas: TimelineLaneCanvas
    let onScroll: (CGFloat) -> Void
    /// The zoom shown during a live zoom, or `nil` once the editor's zoom has caught up.
    let onLiveZoom: (CGFloat?) -> Void
    /// Sets the editor's zoom when a live zoom pauses.
    let onCommitZoom: (CGFloat) -> Void
    /// Any press inside the lanes. Used to give keyboard focus back to the timeline.
    let onPointerDown: () -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> TimelineHorizontalNSScrollView<Content> {
        let view = TimelineHorizontalNSScrollView(rootView: content())
        view.onScroll = onScroll
        view.onLiveZoom = onLiveZoom
        view.onCommitZoom = onCommitZoom
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ view: TimelineHorizontalNSScrollView<Content>, context: Context) {
        view.onScroll = onScroll
        view.onLiveZoom = onLiveZoom
        view.onCommitZoom = onCommitZoom
        view.onPointerDown = onPointerDown
        view.zoomRange = zoomRange
        view.timelineWidth = canvas.contentWidth
        view.update(rootView: content(), contentWidth: contentWidth, contentHeight: contentHeight, zoom: zoom)
        view.canvasView.follow(canvas.hover)
        view.canvasView.update(canvas.scene(in: context.environment))
        view.gridView.follow(canvas.playRangePreview)
        view.gridView.update(canvas.gridScene(in: context.environment))
    }
}

final class TimelineHorizontalNSScrollView<Content: View>: NSScrollView {
    /// A wheel zoom, which has no end event, is handed to SwiftUI once it has been still this long.
    private static var commitDelay: TimeInterval { 0.12 }
    /// A pinch is handed over when it ends. This catches one whose end never arrives, and is
    /// long enough that slowing down mid-pinch does not lay the editor out under the fingers.
    private static var pinchCommitDelay: TimeInterval { 0.6 }

    var onScroll: ((CGFloat) -> Void)?
    var onLiveZoom: ((CGFloat?) -> Void)?
    var onCommitZoom: ((CGFloat) -> Void)?
    var zoomRange: ClosedRange<CGFloat> = 1...1
    /// Width the editor's zoom maps the song's duration to, before display padding.
    var timelineWidth: CGFloat = 0
    var onPointerDown: (() -> Void)? {
        didSet { hostingView.onPointerDown = onPointerDown }
    }

    /// Sits below the clip view and does not scroll. It is redrawn at the new offset in the
    /// same event that moves the content, so the waveforms never lag the clip chrome.
    let canvasView = TimelineLaneCanvasView(frame: .zero)
    /// Above the clip view: the measure grid, drawn over the lanes and the clips.
    let gridView = TimelineGridOverlayView(frame: .zero)
    /// The document view. A live zoom resizes it without touching the SwiftUI inside.
    private let container = TimelineDocumentView()
    private let hostingView: TimelinePointerHostingView<Content>
    private var boundsObserver: NSObjectProtocol?
    /// Scrolls and resizes of the editor's vertical scroll view, which change what is on screen.
    private var verticalObservers: [NSObjectProtocol] = []
    private var zoom: CGFloat?
    /// The zoom on screen while the editor's zoom has not caught up.
    private var liveZoom: CGFloat?
    private var commitTimer: Timer?
    private var pacer: TimelineLiveZoomPacer?
    /// Takes pinches anywhere over the timeline column, rulers included, before SwiftUI does.
    private var magnifyMonitor: Any?

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
        container.addSubview(hostingView)
        documentView = container
        addSubview(canvasView, positioned: .below, relativeTo: contentView)
        addSubview(gridView, positioned: .above, relativeTo: contentView)
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
        verticalObservers.forEach(NotificationCenter.default.removeObserver(_:))
        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
        }
    }

    func update(rootView: Content, contentWidth: CGFloat, contentHeight: CGFloat, zoom: CGFloat) {
        hostingView.rootView = rootView
        let size = NSSize(width: max(0, contentWidth), height: max(0, contentHeight))
        let oldWidth = container.frame.width
        if hostingView.frame.size != size {
            hostingView.setFrameSize(size)
        }
        let isZoom = self.zoom.map { $0 != zoom } ?? false
        self.zoom = zoom
        if isZoom, let liveZoom {
            // The editor has laid out the live zoom, or zoomed some other way mid-gesture. The
            // callback now carries the new layout, so the lanes' painted range is right for it
            // in this same update.
            onLiveZoom?(liveZoom)
            endLiveZoom()
        }
        if liveZoom == nil, container.frame.size != size {
            container.setFrameSize(size)
        }
        // A width change from anything but a zoom, such as a longer song, keeps the offset. A
        // zoom from a menu or the rulers keeps the viewport's center.
        guard isZoom, size.width != oldWidth else { return }
        let target = TimelineLayout.zoomedOffset(
            anchorX: contentView.bounds.width / 2,
            offset: contentView.bounds.origin.x,
            oldWidth: oldWidth,
            newWidth: size.width,
            viewportWidth: contentView.bounds.width
        )
        scrollContent(to: target)
    }

    override func scrollWheel(with event: NSEvent) {
        guard onCommitZoom != nil, let scale = ScrollWheelZoom.scale(for: event) else {
            super.scrollWheel(with: event)
            return
        }
        livePacer.add(scale, anchorX: viewportX(of: event))
        scheduleCommit(after: Self.commitDelay)
    }

    /// Trackpad pinch. Handled here rather than by a SwiftUI gesture so the zoom can keep the
    /// content under the fingers in place.
    override func magnify(with event: NSEvent) {
        guard onCommitZoom != nil else {
            super.magnify(with: event)
            return
        }
        livePacer.add(max(0.1, 1 + event.magnification), anchorX: viewportX(of: event))
        switch event.phase {
        case .ended, .cancelled:
            commitLiveZoom()
        default:
            scheduleCommit(after: Self.pinchCommitDelay)
        }
    }

    private var livePacer: TimelineLiveZoomPacer {
        if let pacer {
            return pacer
        }
        let pacer = TimelineLiveZoomPacer(view: self) { [weak self] scale, anchorX in
            self?.zoomLive(by: scale, anchorX: anchorX)
        }
        self.pacer = pacer
        return pacer
    }

    /// Zooms the canvas, the grid and the scroll position now, keeping the content at viewport
    /// x `anchorX` in place. The editor's zoom follows when the gesture ends.
    func zoomLive(by scale: CGFloat, anchorX: CGFloat) {
        guard let zoom, zoom > 0, timelineWidth > 0, scale != 1 else { return }
        let viewport = contentView.bounds.width
        guard let step = TimelineLayout.liveZoomStep(
            from: liveZoom ?? zoom,
            by: scale,
            range: zoomRange,
            committedZoom: zoom,
            committedWidth: timelineWidth,
            offset: contentView.bounds.origin.x,
            anchorX: anchorX,
            viewportWidth: viewport
        ) else { return }

        liveZoom = step.zoom
        container.setFrameSize(NSSize(width: max(step.contentWidth, viewport), height: container.frame.height))
        // The SwiftUI chrome keeps its layout and is stretched to the new zoom until it catches up.
        container.layer?.sublayerTransform = CATransform3DMakeScale(step.zoom / zoom, 1, 1)
        canvasView.setLiveContentWidth(step.contentWidth)
        gridView.setLiveContentWidth(step.contentWidth)
        // Before the scroll, so the painted range moves once, with the new zoom and offset.
        onLiveZoom?(step.zoom)
        scrollContent(to: step.offset)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            pacer?.stop()
        }
        observeEnclosingScrollView()
        monitorPinches()
    }


    /// A pinch goes to the view under the fingers. Over the rulers that is SwiftUI, whose
    /// gesture lays the whole editor out on every event, so every pinch over this column is
    /// zoomed here instead.
    private func monitorPinches() {
        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            self.magnifyMonitor = nil
        }
        guard window != nil else { return }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, event.window === self.window, self.onCommitZoom != nil else { return event }
            let x = self.convert(event.locationInWindow, from: nil).x
            guard x >= self.bounds.minX, x <= self.bounds.maxX else { return event }
            self.magnify(with: event)
            return nil
        }
    }

    private func scheduleCommit(after delay: TimeInterval) {
        commitTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitLiveZoom() }
        }
        RunLoop.main.add(timer, forMode: .common)
        commitTimer = timer
    }

    private func commitLiveZoom() {
        commitTimer?.invalidate()
        commitTimer = nil
        pacer?.flush()
        guard let liveZoom else { return }
        onCommitZoom?(liveZoom)
    }

    /// Hands the lanes back to SwiftUI at the zoom it has now laid out.
    private func endLiveZoom() {
        commitTimer?.invalidate()
        commitTimer = nil
        let shown = liveZoom
        liveZoom = nil
        container.layer?.sublayerTransform = CATransform3DIdentity
        canvasView.setLiveContentWidth(nil)
        gridView.setLiveContentWidth(nil)
        // The rulers read the live zoom. Clear it after this update, unless a new gesture began.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.liveZoom == nil, shown != nil else { return }
            self.onLiveZoom?(nil)
        }
    }

    private func scrollContent(to x: CGFloat) {
        contentView.scroll(to: NSPoint(x: x, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
    }

    private func viewportX(of event: NSEvent) -> CGFloat {
        contentView.convert(event.locationInWindow, from: nil).x - contentView.bounds.origin.x
    }

    override func tile() {
        super.tile()
        layoutSurfaces()
    }

    /// Sizes the canvas and the grid to the part of the lanes on screen. The lanes are as tall as
    /// every track, inside the editor's vertical scroll view, and both surfaces are redrawn
    /// and handed to the window server on every frame of a zoom. At the lanes' full height,
    /// waiting on those backing stores took most of each frame.
    private func layoutSurfaces() {
        let lanes = contentView.frame
        var slice = lanes.intersection(visibleRect)
        if slice.isNull {
            slice = NSRect(x: lanes.minX, y: lanes.minY, width: lanes.width, height: 0)
        }
        slice.origin.x = lanes.minX
        slice.size.width = lanes.width
        // Each surface keeps drawing in lane coordinates, from the top of the first lane.
        let top = isFlipped ? slice.minY - lanes.minY : lanes.maxY - slice.maxY
        for surface: NSView in [canvasView, gridView] {
            if surface.frame != slice {
                surface.frame = slice
            }
            if surface.bounds.origin.y != top {
                surface.setBoundsOrigin(NSPoint(x: 0, y: top))
                surface.needsDisplay = true
            }
        }
    }

    private func observeEnclosingScrollView() {
        verticalObservers.forEach(NotificationCenter.default.removeObserver(_:))
        verticalObservers = []
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        verticalObservers = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: clipView, queue: nil) { [weak self] _ in
                self?.layoutSurfaces()
            }
        }
        layoutSurfaces()
    }

    private func clipViewBoundsDidChange() {
        let offset = contentView.bounds.origin.x
        canvasView.timelineOffsetDidChange(offset)
        gridView.timelineOffsetDidChange(offset)
        onScroll?(offset)
    }
}

/// Flipped so the SwiftUI lanes keep their top-left origin. Layer-backed, so a live zoom can
/// stretch them with a sublayer transform.
private final class TimelineDocumentView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
