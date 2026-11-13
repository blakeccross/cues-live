#if os(macOS)
import AppKit
import SwiftUI

/// AppKit side of `LiveSetlistScrollHost`: the lane canvas behind the clip view, the song lanes'
/// SwiftUI chrome as the document view, a playhead line above them, and a display link that
/// follows playback.
final class LiveSetlistNSScrollView: NSScrollView {
    private let model: LiveSetlistScrollModel
    private let container = LiveSetlistDocumentView()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let playheadView = LiveSetlistPlayheadNSView()
    private let canvasView = LiveSetlistLaneCanvasView(frame: .zero)
    private var link: CADisplayLink?
    private var observers: [NSObjectProtocol] = []
    /// Set while the clip view moves for a reason other than the user scrolling it.
    private var isAdjusting = false
    var onWheelZoom: ((CGFloat) -> Void)?

    init(model: LiveSetlistScrollModel) {
        self.model = model
        super.init(frame: .zero)
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        verticalScrollElasticity = .none
        hostingView.sizingOptions = []
        container.addSubview(hostingView)
        container.addSubview(playheadView)
        documentView = container
        // Below the transparent clip view, so it stays put while the lanes scroll over it.
        addSubview(canvasView, positioned: .below, relativeTo: contentView)
        contentView.postsBoundsChangedNotifications = true
        observeScrolling()
        model.onLayoutChange = { [weak self] in
            self?.needsLayout = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func update(rootView: AnyView, scene: LiveSetlistLanePainter.Scene) {
        hostingView.rootView = rootView
        canvasView.update(scene)
        link?.isPaused = false
        reposition()
    }

    override func layout() {
        isAdjusting = true
        super.layout()
        isAdjusting = false
        reposition()
    }

    override func tile() {
        let wasAdjusting = isAdjusting
        isAdjusting = true
        super.tile()
        let viewport = contentView.bounds.size
        let size = NSSize(width: max(model.contentWidth, viewport.width), height: viewport.height)
        if container.frame.size != size {
            container.setFrameSize(size)
        }
        if hostingView.frame != container.bounds {
            hostingView.frame = container.bounds
        }
        if canvasView.frame != contentView.frame {
            canvasView.frame = contentView.frame
        }
        isAdjusting = wasAdjusting
        model.setViewportWidth(viewport.width)
    }

    /// Command- and Option-scroll zoom instead of scrolling. The model keeps the playhead's
    /// content in place, as it does for a pinch.
    override func scrollWheel(with event: NSEvent) {
        guard let onWheelZoom, let scale = ScrollWheelZoom.scale(for: event) else {
            super.scrollWheel(with: event)
            return
        }
        if scale != 1 {
            onWheelZoom(scale)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        // The link retains its target; leaving the window above breaks that cycle.
        let link = displayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        model.refreshPlayhead()
        reposition()
        // A stopped transport only moves when the owner re-renders, which resumes the link.
        if !model.needsClock {
            link.isPaused = true
        }
    }

    private func reposition() {
        if let target = model.targetOffset() {
            isAdjusting = true
            contentView.scroll(to: NSPoint(x: target, y: 0))
            reflectScrolledClipView(contentView)
            isAdjusting = false
            model.didScroll(to: contentView.bounds.origin.x, byUser: false)
        }
        if let frame = model.playheadFrame(width: LiveSetlistWaveformMetrics.playheadWidth) {
            playheadView.isHidden = false
            if playheadView.frame != frame {
                playheadView.frame = frame
            }
        } else {
            playheadView.isHidden = true
        }
        canvasView.refresh(from: model, origin: contentView.bounds.origin)
    }

    private func observeScrolling() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.clipViewBoundsDidChange() }
            },
            center.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: self,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.beginUserScroll() }
            },
            center.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: self,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.endUserScroll() }
            },
        ]
    }

    private func clipViewBoundsDidChange() {
        model.didScroll(to: contentView.bounds.origin.x, byUser: !isAdjusting)
        canvasView.refresh(from: model, origin: contentView.bounds.origin)
    }
}

/// Flipped so the lanes and the playhead share SwiftUI's top-left origin.
private final class LiveSetlistDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class LiveSetlistPlayheadNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 1
            shadow.shadowOffset = .zero
            return shadow
        }()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif
