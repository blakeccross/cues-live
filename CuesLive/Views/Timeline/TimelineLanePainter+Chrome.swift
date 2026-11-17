import CoreGraphics
import CoreText
import Foundation

extension TimelineLanePainter {
    /// The bar across the top of a clip, with the track's name.
    func drawHeader(_ clip: TimelineCanvasClip, in lane: Lane, body: CGRect, rect: CGRect, context: CGContext) {
        let header = CGRect(x: body.minX, y: body.minY, width: body.width, height: TimelineLayout.clipHeaderHeight)
        let shown = header.intersection(rect)
        guard !shown.isNull, shown.width > 0 else { return }
        context.setFillColor(clip.isSelected ? lane.selectedHeaderColor : lane.headerColor)
        context.fill(shown)

        let inset = AppSpacing.md
        let available = header.width - inset * 2
        guard available > 0, !lane.name.isEmpty, header.minX + inset < rect.maxX else { return }
        let color = clip.isSelected ? scene.selectedHeaderTextColor : scene.headerTextColor
        guard let line = Self.nameLine(lane.name, color: color, width: available) else { return }
        let font = AppTypography.Compact.labelCTFont
        let baseline = header.midY + (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
        context.saveGState()
        context.clip(to: shown)
        // The canvas is flipped, so text is drawn with its own y axis turned back up.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: header.minX + inset, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// The clip's left, right and bottom edges. A selected clip's border is wider and in the
    /// selected header color, so the border and the header read as one frame.
    func drawBorder(_ clip: TimelineCanvasClip, in lane: Lane, body: CGRect, rect: CGRect, context: CGContext) {
        let width = clip.isSelected ? TimelineLayout.clipSelectionBorderWidth : TimelineLayout.clipBorderWidth
        let top = clip.isSelected ? TimelineLayout.clipHeaderHeight : TimelineLayout.clipBorderWidth
        let sideHeight = max(0, body.height - top)
        let edges = [
            CGRect(x: body.minX, y: body.minY + top, width: width, height: sideHeight),
            CGRect(x: body.maxX - width, y: body.minY + top, width: width, height: sideHeight),
            CGRect(x: body.minX, y: body.maxY - width, width: body.width, height: width),
        ]
        context.setFillColor(clip.isSelected ? lane.selectedHeaderColor : lane.borderColor)
        for edge in edges {
            let shown = edge.intersection(rect)
            if !shown.isNull, shown.width > 0 { context.fill(shown) }
        }
    }

    /// The name as one line, cut short with an ellipsis when it does not fit in `width`.
    private static func nameLine(_ name: String, color: CGColor, width: CGFloat) -> CTLine? {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): AppTypography.Compact.labelCTFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: name, attributes: attributes))
        guard CTLineGetTypographicBounds(line, nil, nil, nil) > Double(width) else { return line }
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis)
    }
}
