#if os(macOS)
import AppKit
import CoreText

/// Draws the rulers above the lanes during a live zoom: the time ruler with its in and out
/// flags, then the meter, tempo and section rows. Each row matches its SwiftUI view, which this
/// covers until the editor has laid out the new zoom.
///
/// It draws in viewport coordinates from the scroll offset and the zoom on screen, like the lane
/// canvas, so a zoom step redraws it without laying out any SwiftUI.
@MainActor
final class TimelineLiveRulerPainter {
    /// A section block, with its colors resolved for its selected and cued state.
    struct Section: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let name: String
        let loops: Bool
        let fillColor: CGColor
        let textColor: CGColor
    }

    /// A meter or tempo segment's value.
    struct Value: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    struct Scene: Equatable {
        var duration: TimeInterval = 1
        /// The width the editor has laid out, before display padding.
        var contentWidth: CGFloat = 1
        var sections: [Section] = []
        var meter: [Value] = []
        var tempo: [Value] = []
        var playRange: ClosedRange<TimeInterval> = 0...1
        var backgroundColor = CGColor(gray: 0.2, alpha: 1)
        var tickColor = CGColor(gray: 0.5, alpha: 0.5)
        var valueColor = CGColor(gray: 0.6, alpha: 1)
        var dividerColor = CGColor(gray: 0, alpha: 0.3)
        var changeMarkerColor = CGColor(gray: 0.5, alpha: 1)
        var flagColor = CGColor(gray: 0.5, alpha: 1)
        var outsidePlayRangeColor = CGColor(gray: 0, alpha: 0.3)
        var playRangeEdgeShadowColor = CGColor(gray: 0, alpha: 0.3)
        var blockBorderColor = CGColor(gray: 0, alpha: 0.5)
    }

    static let labelTop: CGFloat = 3
    static let flagWidth: CGFloat = 13
    static let pennantHeight: CGFloat = 16

    private(set) var scene = Scene()
    /// Horizontal scroll offset in content points at the zoom on screen.
    var offset: CGFloat = 0
    /// The content width at the zoom on screen.
    var contentWidth: CGFloat = 1
    var viewportWidth: CGFloat = 0

    /// Returns `true` when the scene changed and needs drawing.
    func update(_ scene: Scene) -> Bool {
        guard scene != self.scene else { return false }
        self.scene = scene
        return true
    }

    /// Width the rulers lay out across: the content, or the viewport when the content is narrower.
    var displayWidth: CGFloat {
        max(contentWidth, viewportWidth)
    }

    /// Draws `rect`, in view coordinates.
    func draw(in context: CGContext, rect: CGRect) {
        guard contentWidth > 0 else { return }
        context.setFillColor(scene.backgroundColor)
        context.fill(rect)
        drawTimeRow(in: context, rect: rect)
        var top = TimelineLayout.rulerHeight
        drawValueRow(scene.meter, top: top, height: TimelineLayout.timeSignatureRulerHeight, minimumLabelWidth: 0, in: context)
        top += TimelineLayout.timeSignatureRulerHeight
        drawValueRow(
            scene.tempo,
            top: top,
            height: TimelineLayout.tempoRulerHeight,
            minimumLabelWidth: TimelineRulerSegment<TempoChange>.minimumLabeledWidth,
            in: context
        )
        top += TimelineLayout.tempoRulerHeight
        drawSectionRow(top: top, height: TimelineLayout.sectionMarkerHeight, rect: rect, in: context)
        drawDivider(atBottomOf: top + TimelineLayout.sectionMarkerHeight, in: context)
    }

    /// View x of `time` at the zoom on screen.
    func x(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: max(scene.duration, 0.001), contentWidth: contentWidth) - offset
    }

    func drawDivider(atBottomOf bottom: CGFloat, in context: CGContext) {
        context.setFillColor(scene.dividerColor)
        context.fill(CGRect(x: 0, y: bottom - 1, width: viewportWidth, height: 1))
    }

    // MARK: - Time ruler

    private func drawTimeRow(in context: CGContext, rect: CGRect) {
        let height = TimelineLayout.rulerHeight
        let duration = max(scene.duration, 0.001)
        let pixelsPerSecond = contentWidth / CGFloat(duration)
        let scale = TimelineTimeRulerScale(pixelsPerSecond: pixelsPerSecond)
        if scale.minor > 0, pixelsPerSecond > 0 {
            drawTicks(scale: scale, pixelsPerSecond: pixelsPerSecond, height: height, rect: rect, in: context)
        }
        drawPlayRange(height: height, in: context)
        drawDivider(atBottomOf: height, in: context)
    }

    /// The same ticks and labels as `TimelineTimeRulerView`, for the part of the content in `rect`.
    private func drawTicks(
        scale: TimelineTimeRulerScale,
        pixelsPerSecond: CGFloat,
        height: CGFloat,
        rect: CGRect,
        in context: CGContext
    ) {
        let duration = max(scene.duration, 0.001)
        let maximumTime = displayWidth > contentWidth ? duration * TimeInterval(displayWidth / contentWidth) : duration
        let subdivisions = max(1, Int((scale.major / scale.minor).rounded()))
        let lastStep = Int((maximumTime / scale.minor).rounded(.down))
        let lower = rect.minX + offset
        let upper = rect.maxX + offset
        // Start on a labeled tick left of the rect, so a label straddling its edge still draws.
        let startStep = Int((Double(lower / pixelsPerSecond) / scale.minor).rounded(.down))
        let firstStep = max(0, startStep - startStep % subdivisions - subdivisions)
        let endStep = min(lastStep, Int((Double(upper / pixelsPerSecond) / scale.minor).rounded(.up)))
        guard firstStep <= endStep else { return }

        let minorLength = min(4, height)
        let majorLength = min(max(9, height * 0.46), height)
        let ticks = CGMutablePath()
        for step in firstStep...endStep {
            let x = x(for: Double(step) * scale.minor)
            guard x + offset <= displayWidth + 1 else { break }
            let length = step % subdivisions == 0 ? majorLength : minorLength
            ticks.move(to: CGPoint(x: x, y: height))
            ticks.addLine(to: CGPoint(x: x, y: height - length))
        }
        context.setStrokeColor(scene.tickColor)
        context.setLineWidth(1)
        context.addPath(ticks)
        context.strokePath()

        let font = AppTypography.Compact.timecodeCTFont
        let baseline = Self.labelTop + CTFontGetAscent(font)
        for step in stride(from: firstStep, through: endStep, by: subdivisions) {
            let x = x(for: Double(step) * scale.minor)
            guard x + offset <= displayWidth - 8 else { break }
            drawText(scale.label(for: Double(step) * scale.minor), font: font, color: scene.valueColor, x: x + 4, baseline: baseline, in: context)
        }
    }

    /// The wash outside the in and out points and their pennants, as `TimelinePlayRangeFlags` draws them.
    private func drawPlayRange(height: CGFloat, in context: CGContext) {
        let inX = x(for: scene.playRange.lowerBound)
        let outX = x(for: scene.playRange.upperBound)
        let end = displayWidth - offset
        context.setFillColor(scene.outsidePlayRangeColor)
        context.fill(CGRect(x: -offset, y: 0, width: max(0, inX + offset), height: height))
        context.fill(CGRect(x: outX, y: 0, width: max(0, end - outX), height: height))
        TimelineGridPainter.fillEdgeShadow(
            CGRect(x: outX, y: 0, width: TimelinePlayRangeEdgeShadow.width, height: height),
            color: scene.playRangeEdgeShadowColor,
            in: context
        )
        drawFlag(at: inX, pointsBack: false, height: height, in: context)
        drawFlag(at: outX, pointsBack: true, height: height, in: context)
    }

    private func drawFlag(at x: CGFloat, pointsBack: Bool, height: CGFloat, in context: CGContext) {
        let minX = min(x, displayWidth - offset - Self.flagWidth)
        let pennant = min(Self.pennantHeight, height)
        let baseX = pointsBack ? minX + Self.flagWidth : minX
        let tipX = pointsBack ? minX : minX + Self.flagWidth
        context.setFillColor(scene.flagColor)
        context.move(to: CGPoint(x: baseX, y: 0))
        context.addLine(to: CGPoint(x: tipX, y: pennant / 2))
        context.addLine(to: CGPoint(x: baseX, y: pennant))
        context.closePath()
        context.fillPath()
    }

    // MARK: - Text

    /// Draws one line of text from `x` along `baseline`, and returns its width.
    @discardableResult
    func drawText(_ string: String, font: CTFont, color: CGColor, x: CGFloat, baseline: CGFloat, in context: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.saveGState()
        // The view is flipped, so text is drawn with its own y axis turned back up.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Baseline that centers `font`'s line on `midY` where SwiftUI would. SwiftUI lays a line out
    /// in a box from the ascent and the descent, each rounded up to a whole point, and centers that.
    static func baseline(centering font: CTFont, on midY: CGFloat) -> CGFloat {
        let ascent = CTFontGetAscent(font)
        let lineHeight = ascent.rounded(.up) + CTFontGetDescent(font).rounded(.up)
        return midY - lineHeight / 2 + ascent
    }
}
#endif
