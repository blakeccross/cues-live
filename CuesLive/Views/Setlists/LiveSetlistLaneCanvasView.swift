#if os(macOS)
import AppKit

/// Viewport-wide surface the setlist lane painter draws into, owned by the setlist scroll view.
final class LiveSetlistLaneCanvasView: NSView {
    private let painter = LiveSetlistLanePainter()

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

    func update(_ scene: LiveSetlistLanePainter.Scene) {
        if painter.update(scene) {
            needsDisplay = true
        }
    }

    /// Redraws when a lane, the scroll offset or the playhead moved on screen.
    func refresh(from model: LiveSetlistScrollModel, origin: CGPoint) {
        if painter.update(from: model, origin: origin) {
            needsDisplay = true
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
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

    private func updateScale() {
        painter.scale = max(window?.backingScaleFactor ?? 2, 1)
        needsDisplay = true
    }
}
#else
import UIKit

/// Viewport-wide surface the setlist lane painter draws into, owned by the setlist scroll view.
final class LiveSetlistLaneCanvasView: UIView {
    private let painter = LiveSetlistLanePainter()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
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

    func update(_ scene: LiveSetlistLanePainter.Scene) {
        if painter.update(scene) {
            setNeedsDisplay()
        }
    }

    /// Redraws when a lane, the scroll offset or the playhead moved on screen.
    func refresh(from model: LiveSetlistScrollModel, origin: CGPoint) {
        if painter.update(from: model, origin: origin) {
            setNeedsDisplay()
        }
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
