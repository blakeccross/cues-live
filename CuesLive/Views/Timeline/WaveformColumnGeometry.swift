import CoreGraphics

/// One pixel column of a waveform: the lowest and highest sample in that window.
struct WaveformColumnSpan: Equatable, Sendable {
    var min: Float
    var max: Float
}

/// Shared with the editor's clip waveform so a summed live lane uses the same column shape.
enum WaveformColumnGeometry {
    /// Fraction of the band height from the center to full scale.
    static let amplitudeFraction: CGFloat = 0.46

    /// Silence stays at least a pixel tall, matching the editor.
    static func thicken(min minValue: Float, max maxValue: Float, half: CGFloat, scale: CGFloat) -> WaveformColumnSpan {
        let pixel = Float((1 / max(scale, 1)) / max(half, 1) / 2)
        guard maxValue - minValue < pixel * 2 else {
            return WaveformColumnSpan(min: minValue, max: maxValue)
        }
        let mid = (minValue + maxValue) / 2
        return WaveformColumnSpan(min: mid - pixel, max: mid + pixel)
    }

    static func envelopePath(
        columns: [WaveformColumnSpan],
        originX: CGFloat,
        columnWidth: CGFloat,
        centerY: CGFloat,
        half: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        guard let first = columns.first, let last = columns.indices.last else { return path }
        func x(_ index: Int) -> CGFloat { originX + CGFloat(index) * columnWidth }
        func y(_ value: Float) -> CGFloat { centerY - CGFloat(clampedAmplitude(value)) * half }

        path.move(to: CGPoint(x: x(0), y: y(first.max)))
        for (index, column) in columns.enumerated() {
            path.addLine(to: CGPoint(x: x(index) + columnWidth * 0.5, y: y(column.max)))
        }
        path.addLine(to: CGPoint(x: x(last) + columnWidth, y: y(columns[last].max)))
        path.addLine(to: CGPoint(x: x(last) + columnWidth, y: y(columns[last].min)))
        for (index, column) in columns.enumerated().reversed() {
            path.addLine(to: CGPoint(x: x(index) + columnWidth * 0.5, y: y(column.min)))
        }
        path.closeSubpath()
        return path
    }

    static func clampedAmplitude(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value))
    }
}
