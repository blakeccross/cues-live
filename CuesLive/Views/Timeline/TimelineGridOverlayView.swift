#if os(macOS)
import AppKit

/// Viewport-wide surface above the lanes that the measure grid is drawn into. It passes every
/// click through to the lanes below.
final class TimelineGridOverlayView: NSView, TimelineOffsetFollowing, TimelinePlayRangeFollowing {
    private let painter = TimelineGridPainter()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(_ scene: TimelineGridPainter.Scene) {
        if painter.update(scene) {
            needsDisplay = true
        }
    }

    func timelineOffsetDidChange(_ offset: CGFloat) {
        guard painter.offset != offset else { return }
        painter.offset = offset
        needsDisplay = true
    }

    func setLiveContentWidth(_ width: CGFloat?) {
        guard painter.liveContentWidth != width else { return }
        painter.liveContentWidth = width
        needsDisplay = true
    }

    /// Shades the lanes from `preview` while a flag is dragged, outside SwiftUI updates.
    func follow(_ preview: TimelinePlayRangePreview) {
        guard preview.laneShade !== self else { return }
        preview.laneShade = self
        playRangePreviewDidChange(preview.range)
    }

    func playRangePreviewDidChange(_ range: ClosedRange<TimeInterval>?) {
        guard painter.previewRange != range else { return }
        painter.previewRange = range
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
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
import SwiftUI
import UIKit

/// Viewport-wide surface above the lanes that the measure grid is drawn into. A horizontal
/// scroll redraws it in the same frame.
final class TimelineGridOverlayView: UIView, TimelineOffsetFollowing, TimelinePlayRangeFollowing {
    private let painter = TimelineGridPainter()
    private weak var scrollModel: TimelineHorizontalScrollModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func follow(_ model: TimelineHorizontalScrollModel?) {
        guard model !== scrollModel else { return }
        scrollModel = model
        model?.gridOverlay = self
        painter.offset = model?.offset ?? 0
        setNeedsDisplay()
    }

    func update(_ scene: TimelineGridPainter.Scene) {
        if painter.update(scene) {
            setNeedsDisplay()
        }
    }

    func timelineOffsetDidChange(_ offset: CGFloat) {
        guard painter.offset != offset else { return }
        painter.offset = offset
        setNeedsDisplay()
    }

    /// Shades the lanes from `preview` while a flag is dragged, outside SwiftUI updates.
    func follow(_ preview: TimelinePlayRangePreview) {
        guard preview.laneShade !== self else { return }
        preview.laneShade = self
        playRangePreviewDidChange(preview.range)
    }

    func playRangePreviewDidChange(_ range: ClosedRange<TimeInterval>?) {
        guard painter.previewRange != range else { return }
        painter.previewRange = range
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        painter.draw(in: context, rect: rect)
    }
}

/// The measure grid over the horizontal `ScrollView`, following the scroll model's offset.
struct TimelineGridOverlayLayer: UIViewRepresentable {
    let canvas: TimelineLaneCanvas
    let scrollModel: TimelineHorizontalScrollModel

    func makeUIView(context: Context) -> TimelineGridOverlayView {
        TimelineGridOverlayView(frame: .zero)
    }

    func updateUIView(_ view: TimelineGridOverlayView, context: Context) {
        view.follow(scrollModel)
        view.follow(canvas.playRangePreview)
        view.update(canvas.gridScene(in: context.environment))
    }
}
#endif
