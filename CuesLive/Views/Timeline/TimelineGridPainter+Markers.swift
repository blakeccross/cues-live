import CoreGraphics
import Foundation

extension TimelineGridPainter {
    /// Section starts, as lines through every lane, then the wash outside the in and out points
    /// with a short shadow past the out point.
    func drawMarkers(in context: CGContext, rect: CGRect, width: CGFloat) {
        let lines = CGMutablePath()
        for time in scene.sectionTimes {
            let x = x(for: time, width: width)
            guard x > rect.minX, x < rect.maxX else { continue }
            lines.move(to: CGPoint(x: x, y: rect.minY))
            lines.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        context.setStrokeColor(scene.sectionLineColor)
        context.setLineWidth(1)
        context.addPath(lines)
        context.strokePath()

        guard let range = previewRange ?? scene.playRange else { return }
        let inX = x(for: range.lowerBound, width: width)
        let outX = x(for: range.upperBound, width: width)
        context.setFillColor(scene.outsidePlayRangeColor)
        if inX > rect.minX {
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: min(inX, rect.maxX) - rect.minX, height: rect.height))
        }
        guard outX < rect.maxX else { return }
        let start = max(rect.minX, outX)
        context.fill(CGRect(x: start, y: rect.minY, width: rect.maxX - start, height: rect.height))
        let shadow = CGRect(x: outX, y: rect.minY, width: TimelinePlayRangeEdgeShadow.width, height: rect.height)
        Self.fillEdgeShadow(shadow, color: scene.playRangeEdgeShadowColor, in: context)
    }

    /// `TimelinePlayRangeEdgeShadow`'s gradient: `color` at the leading edge, clear at the trailing.
    static func fillEdgeShadow(_ rect: CGRect, color: CGColor, in context: CGContext) {
        guard let clear = color.copy(alpha: 0),
              let gradient = CGGradient(colorsSpace: nil, colors: [color, clear] as CFArray, locations: [0, 1])
        else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
        context.restoreGState()
    }
}
