#if os(macOS)
import AppKit

/// Viewport-wide surface the lane painter draws into, owned by the horizontal scroll view.
final class TimelineLaneCanvasView: NSView {
    private let painter = TimelineLanePainter()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        painter.onNeedsDisplay = { [weak self] in
            self?.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(_ scene: TimelineLanePainter.Scene) {
        if painter.update(scene) {
            needsDisplay = true
        }
    }

    func timelineOffsetDidChange(_ offset: CGFloat) {
        guard painter.offset != offset else { return }
        painter.offset = offset
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        painter.scale = max(window?.backingScaleFactor ?? 2, 1)
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        painter.scale = max(window?.backingScaleFactor ?? 2, 1)
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = dirtyRect.intersection(bounds)
        guard !rect.isNull, !rect.isEmpty else { return }
        painter.draw(in: context, rect: rect)
    }
}
#else
import UIKit

/// Viewport-wide surface the lane painter draws into. A horizontal scroll redraws it in the
/// same frame.
final class TimelineLaneCanvasView: UIView, TimelineOffsetFollowing {
    private let painter = TimelineLanePainter()
    private weak var scrollModel: TimelineHorizontalScrollModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
        painter.onNeedsDisplay = { [weak self] in
            self?.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func follow(_ model: TimelineHorizontalScrollModel?) {
        guard model !== scrollModel else { return }
        scrollModel = model
        model?.laneCanvas = self
        painter.offset = model?.offset ?? 0
        setNeedsDisplay()
    }

    func update(_ scene: TimelineLanePainter.Scene) {
        if painter.update(scene) {
            setNeedsDisplay()
        }
    }

    func timelineOffsetDidChange(_ offset: CGFloat) {
        guard painter.offset != offset else { return }
        painter.offset = offset
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        painter.scale = max(traitCollection.displayScale, 1)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        painter.draw(in: context, rect: rect)
    }
}
#endif
