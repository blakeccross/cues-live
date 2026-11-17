#if os(macOS)
import AppKit
import SwiftUI

/// Covers the SwiftUI rulers during a live zoom and draws them at the zoom on screen. Hidden
/// otherwise, so the SwiftUI rulers underneath handle every click and drag.
final class TimelineLiveRulerView: NSView, TimelineLiveZoomFollowing {
    private let painter = TimelineLiveRulerPainter()
    private weak var scrollModel: TimelineHorizontalScrollModel?
    /// The zoom on screen over the zoom the scene was laid out at.
    private var scale: CGFloat = 1

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // Labels and blocks that start left of the viewport would otherwise draw over the
        // track names: views no longer clip by default on macOS 14.
        clipsToBounds = true
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func follow(_ model: TimelineHorizontalScrollModel) {
        guard model !== scrollModel else { return }
        scrollModel = model
        model.liveRuler = self
    }

    func update(_ scene: TimelineLiveRulerPainter.Scene) {
        guard painter.update(scene) else { return }
        painter.contentWidth = scene.contentWidth * scale
        if !isHidden {
            needsDisplay = true
        }
    }

    func liveZoomDidChange(scale: CGFloat?, offset: CGFloat) {
        guard let scale else {
            isHidden = true
            return
        }
        self.scale = scale
        painter.contentWidth = painter.scene.contentWidth * scale
        painter.offset = offset
        isHidden = false
        needsDisplay = true
    }

    func timelineOffsetDidChange(_ offset: CGFloat) {
        guard painter.offset != offset else { return }
        painter.offset = offset
        if !isHidden {
            needsDisplay = true
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        painter.viewportWidth = newSize.width
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = dirtyRect.intersection(bounds)
        guard !rect.isNull, !rect.isEmpty else { return }
        painter.draw(in: context, rect: rect)
    }
}

/// The live-zoom ruler over the editor's rulers, following the scroll model.
struct TimelineLiveRulerLayer: NSViewRepresentable {
    let ruler: TimelineLiveRuler
    let scrollModel: TimelineHorizontalScrollModel

    func makeNSView(context: Context) -> TimelineLiveRulerView {
        TimelineLiveRulerView(frame: .zero)
    }

    func updateNSView(_ view: TimelineLiveRulerView, context: Context) {
        view.follow(scrollModel)
        view.update(ruler.scene(in: context.environment))
    }
}
#endif
