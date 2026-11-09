import SwiftUI

/// One pixel column of a waveform: the lowest and highest sample in that window.
struct WaveformColumnSpan: Equatable, Sendable {
    var min: Float
    var max: Float
}

/// Shared with the editor's clip waveform so a summed live lane uses the same column shape.
enum WaveformColumnGeometry {
    /// Fraction of the band height from the center to full scale.
    static let amplitudeFraction: CGFloat = 0.46

    struct Prepared {
        var originX: CGFloat
        var columnWidth: CGFloat
        var columns: [WaveformColumnSpan]
    }

    /// Silence stays at least a pixel tall, matching the editor.
    static func thicken(min minValue: Float, max maxValue: Float, half: CGFloat, scale: CGFloat) -> WaveformColumnSpan {
        let pixel = Float((1 / max(scale, 1)) / max(half, 1) / 2)
        guard maxValue - minValue < pixel * 2 else {
            return WaveformColumnSpan(min: minValue, max: maxValue)
        }
        let mid = (minValue + maxValue) / 2
        return WaveformColumnSpan(min: mid - pixel, max: mid + pixel)
    }

    /// One column per device pixel. Each column covers one point of content and reaches
    /// halfway into its neighbors, the same window the editor uses.
    static func prepare(
        mins: [Float],
        maxes: [Float],
        contentWidth: CGFloat,
        rect: CGRect,
        scale: CGFloat,
        half: CGFloat
    ) -> Prepared? {
        let count = min(mins.count, maxes.count)
        guard count > 0, contentWidth > 0, rect.width > 0 else { return nil }
        let scale = max(scale, 1)
        let pixelStart = Int(floor(rect.minX * scale))
        let pixelEnd = Int(ceil(rect.maxX * scale))
        let columnCount = pixelEnd - pixelStart
        guard columnCount > 0 else { return nil }

        let framesPerPoint = Double(count) / Double(contentWidth)
        let step = framesPerPoint / Double(scale)
        let overlap = max(0, framesPerPoint - step)
        let windowStart = Double(pixelStart) / Double(scale) * framesPerPoint - overlap * 0.5

        var columns: [WaveformColumnSpan] = []
        columns.reserveCapacity(columnCount)
        for column in 0..<columnCount {
            let lower = windowStart + step * Double(column)
            let upper = lower + step + overlap
            var low = Float.infinity
            var high = -Float.infinity
            if upper >= 0, lower <= Double(count - 1) {
                let from = max(0, Int(floor(lower)))
                let end = min(count, max(from + 1, Int(ceil(upper))))
                if from < end {
                    for index in from..<end {
                        low = min(low, mins[index])
                        high = max(high, maxes[index])
                    }
                }
            }
            if low <= high {
                columns.append(thicken(min: low, max: high, half: half, scale: scale))
            } else {
                columns.append(thicken(min: 0, max: 0, half: half, scale: scale))
            }
        }
        return Prepared(originX: CGFloat(pixelStart) / scale, columnWidth: 1 / scale, columns: columns)
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

enum WaveformRenderStyle: Equatable {
    case filledEnvelope
    case voiceMemosBars
}

struct WaveformBarsCanvas: View, Equatable {
    let bars: [Float]
    var showsEmptyBaseline = true
    var baselineRanges: [ClosedRange<CGFloat>] = []
    var headerHeight: CGFloat = 0
    var fillColor: Color = Color.dawWaveformFill
    var style: WaveformRenderStyle = .filledEnvelope
    var playheadFraction: CGFloat?
    var playedColor: Color = Color.liveVoiceMemosPlayed
    var unplayedColor: Color = Color.liveVoiceMemosUnplayed
    /// Metal offscreens help short static waveforms but thrash scroll for
    /// setlist-length lanes (tens of thousands of points wide).
    var usesDrawingGroup = true
    /// Summed min/max series. When present, the filled envelope uses editor columns.
    var columnMins: [Float] = []
    var columnMaxes: [Float] = []
    /// Lane width the series spans. `0` means the canvas is the whole lane.
    var columnContentWidth: CGFloat = 0
    /// Content-x of this canvas's left edge.
    var columnOriginX: CGFloat = 0

    @Environment(\.displayScale) private var displayScale

    static func == (lhs: WaveformBarsCanvas, rhs: WaveformBarsCanvas) -> Bool {
        lhs.bars == rhs.bars
            && lhs.showsEmptyBaseline == rhs.showsEmptyBaseline
            && lhs.baselineRanges == rhs.baselineRanges
            && lhs.headerHeight == rhs.headerHeight
            && lhs.fillColor == rhs.fillColor
            && lhs.style == rhs.style
            && lhs.playheadFraction == rhs.playheadFraction
            && lhs.playedColor == rhs.playedColor
            && lhs.unplayedColor == rhs.unplayedColor
            && lhs.usesDrawingGroup == rhs.usesDrawingGroup
            && lhs.columnMins == rhs.columnMins
            && lhs.columnMaxes == rhs.columnMaxes
            && lhs.columnContentWidth == rhs.columnContentWidth
            && lhs.columnOriginX == rhs.columnOriginX
    }

    private let minBarHeight: CGFloat = 1.0
    private let voiceMemosMinBarHeight: CGFloat = 2.0

    var body: some View {
        let scale = max(displayScale, 1)
        let canvas = Canvas { context, size in
            drawWaveform(in: &context, size: size, scale: scale)
        }
        // `drawingGroup()` helps short static waveforms, but forces a huge Metal
        // offscreen while `playheadFraction` animates or when the lane is very wide.
        if usesDrawingGroup, playheadFraction == nil {
            canvas.drawingGroup()
        } else {
            canvas
        }
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        switch style {
        case .filledEnvelope:
            drawFilledEnvelopeWaveform(in: &context, size: size, scale: scale)
        case .voiceMemosBars:
            drawVoiceMemosBars(in: &context, size: size)
        }
    }

    private func drawFilledEnvelopeWaveform(in context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        if !columnMins.isEmpty, !columnMaxes.isEmpty {
            drawMinMaxColumns(in: &context, size: size, scale: scale)
            return
        }

        let playheadX = playheadFraction.map { min(max(0, $0), 1) * size.width }
        guard let playheadX else {
            drawFilledEnvelopeBody(in: &context, size: size, fillColor: fillColor)
            return
        }

        let usesCustomFill = fillColor != Color.dawWaveformFill
        let playedFill = usesCustomFill
            ? fillColor.opacity(LiveSetlistWaveformMetrics.waveformPlayedOpacity)
            : playedColor
        let unplayedFill = usesCustomFill
            ? fillColor.opacity(LiveSetlistWaveformMetrics.waveformUnplayedOpacity)
            : unplayedColor

        // Draw each side once. Overlaying the played fill on the unplayed fill
        // would stack the alphas and jump brighter than the played opacity.
        var unplayedContext = context
        unplayedContext.clip(
            to: Path(CGRect(
                x: playheadX,
                y: 0,
                width: max(0, size.width - playheadX),
                height: size.height
            ))
        )
        drawFilledEnvelopeBody(in: &unplayedContext, size: size, fillColor: unplayedFill)

        var playedContext = context
        playedContext.clip(
            to: Path(CGRect(x: 0, y: 0, width: max(0, playheadX), height: size.height))
        )
        drawFilledEnvelopeBody(in: &playedContext, size: size, fillColor: playedFill)
    }

    private func drawMinMaxColumns(in context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let bodyHeight = max(1, size.height - headerHeight)
        let half = bodyHeight * WaveformColumnGeometry.amplitudeFraction
        let centerY = headerHeight + bodyHeight / 2
        let contentWidth = columnContentWidth > 0 ? columnContentWidth : size.width
        guard let prepared = WaveformColumnGeometry.prepare(
            mins: columnMins,
            maxes: columnMaxes,
            contentWidth: contentWidth,
            rect: CGRect(x: columnOriginX, y: 0, width: size.width, height: size.height),
            scale: scale,
            half: half
        ) else {
            drawFilledEnvelopeBody(in: &context, size: size, fillColor: fillColor)
            return
        }

        let path = Path(WaveformColumnGeometry.envelopePath(
            columns: prepared.columns,
            originX: prepared.originX - columnOriginX,
            columnWidth: prepared.columnWidth,
            centerY: centerY,
            half: half
        ))
        var clipped = context
        clipped.clip(to: Path(CGRect(origin: .zero, size: size)))

        guard let playheadX = playheadFraction.map({ min(max(0, $0), 1) * size.width }) else {
            clipped.fill(path, with: .color(fillColor))
            return
        }

        let usesCustomFill = fillColor != Color.dawWaveformFill
        let playedFill = usesCustomFill
            ? fillColor.opacity(LiveSetlistWaveformMetrics.waveformPlayedOpacity)
            : playedColor
        let unplayedFill = usesCustomFill
            ? fillColor.opacity(LiveSetlistWaveformMetrics.waveformUnplayedOpacity)
            : unplayedColor

        var unplayedContext = clipped
        unplayedContext.clip(to: Path(CGRect(
            x: playheadX,
            y: 0,
            width: max(0, size.width - playheadX),
            height: size.height
        )))
        unplayedContext.fill(path, with: .color(unplayedFill))

        var playedContext = clipped
        playedContext.clip(to: Path(CGRect(x: 0, y: 0, width: max(0, playheadX), height: size.height)))
        playedContext.fill(path, with: .color(playedFill))
    }

    private func drawFilledEnvelopeBody(
        in context: inout GraphicsContext,
        size: CGSize,
        fillColor: Color
    ) {
        let bodyHeight = max(1, size.height - headerHeight)
        let midY = headerHeight + bodyHeight / 2

        if !bars.isEmpty {
            let barWidth = size.width / CGFloat(bars.count)
            let maxBarHeight = (bodyHeight / 2) * 0.92

            if baselineRanges.isEmpty {
                drawFilledWaveformSegment(
                    in: &context,
                    range: 0...(size.width),
                    bars: bars,
                    barWidth: barWidth,
                    midY: midY,
                    maxBarHeight: maxBarHeight,
                    fillColor: fillColor
                )
            } else {
                for range in baselineRanges {
                    drawFilledWaveformSegment(
                        in: &context,
                        range: range,
                        bars: bars,
                        barWidth: barWidth,
                        midY: midY,
                        maxBarHeight: maxBarHeight,
                        fillColor: fillColor
                    )
                }
            }
        } else if showsEmptyBaseline {
            let ranges = baselineRanges.isEmpty ? [0...(size.width)] : baselineRanges
            for range in ranges {
                let startX = max(0, range.lowerBound)
                let endX = min(size.width, range.upperBound)
                drawSilentSegment(in: &context, startX: startX, endX: endX, midY: midY, fillColor: fillColor)
            }
        }
    }

    private func drawVoiceMemosBars(in context: inout GraphicsContext, size: CGSize) {
        let bodyHeight = max(1, size.height - headerHeight)
        let midY = headerHeight + bodyHeight / 2
        let maxBarHeight = bodyHeight * 0.88
        let playheadX = playheadFraction.map { min(max(0, $0), 1) * size.width }

        if !bars.isEmpty {
            let barSlotWidth = size.width / CGFloat(bars.count)
            let barWidth = min(max(1.5, barSlotWidth * 0.55), 4.0)
            let cornerRadius = barWidth / 2

            let ranges = baselineRanges.isEmpty ? [0...(size.width)] : baselineRanges
            for range in ranges {
                let startX = max(0, range.lowerBound)
                let endX = min(size.width, range.upperBound)
                guard endX > startX else { continue }

                let startIndex = max(0, Int(floor(startX / barSlotWidth)))
                let endIndex = min(bars.count - 1, Int(floor((endX - 0.001) / barSlotWidth)))
                guard startIndex <= endIndex else { continue }

                for index in startIndex...endIndex {
                    let centerX = CGFloat(index) * barSlotWidth + barSlotWidth * 0.5
                    let amplitude = CGFloat(bars[index])
                    let barHeight = max(voiceMemosMinBarHeight, amplitude * maxBarHeight)
                    let color = voiceMemosBarColor(at: centerX, playheadX: playheadX)
                    let rect = CGRect(
                        x: centerX - barWidth / 2,
                        y: midY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: cornerRadius),
                        with: .color(color)
                    )
                }
            }
        } else if showsEmptyBaseline {
            let ranges = baselineRanges.isEmpty ? [0...(size.width)] : baselineRanges
            for range in ranges {
                drawVoiceMemosSilentSegment(
                    in: &context,
                    startX: max(0, range.lowerBound),
                    endX: min(size.width, range.upperBound),
                    midY: midY,
                    bodyHeight: bodyHeight,
                    fillColor: fillColor
                )
            }
        }
    }

    private func voiceMemosBarColor(at centerX: CGFloat, playheadX: CGFloat?) -> Color {
        guard let playheadX else {
            return fillColor == Color.dawWaveformFill ? unplayedColor : fillColor
        }

        let usesCustomFill = fillColor != Color.dawWaveformFill
        let activeColor = usesCustomFill
            ? fillColor.opacity(LiveSetlistWaveformMetrics.waveformPlayedOpacity)
            : playedColor
        let inactiveColor = usesCustomFill
            ? fillColor.opacity(LiveSetlistWaveformMetrics.waveformUnplayedOpacity)
            : unplayedColor
        return centerX <= playheadX ? activeColor : inactiveColor
    }

    private func drawVoiceMemosSilentSegment(
        in context: inout GraphicsContext,
        startX: CGFloat,
        endX: CGFloat,
        midY: CGFloat,
        bodyHeight: CGFloat,
        fillColor: Color
    ) {
        guard endX > startX else { return }

        let span = endX - startX
        // Long empty lanes (e.g. 79‑minute songs still loading) must not mint
        // thousands of rounded rects — a thin baseline is enough.
        if span > 400 {
            let barHeight = min(voiceMemosMinBarHeight, bodyHeight * 0.08)
            let rect = CGRect(
                x: startX,
                y: midY - barHeight / 2,
                width: span,
                height: barHeight
            )
            context.fill(Path(rect), with: .color(fillColor.opacity(0.55)))
            return
        }

        let barSlotWidth: CGFloat = 3
        let barWidth: CGFloat = 2
        let cornerRadius = barWidth / 2
        let barHeight = min(voiceMemosMinBarHeight, bodyHeight * 0.08)
        var centerX = startX + barSlotWidth / 2

        while centerX < endX {
            let rect = CGRect(
                x: centerX - barWidth / 2,
                y: midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: cornerRadius),
                with: .color(fillColor.opacity(0.55))
            )
            centerX += barSlotWidth
        }
    }

    private func drawFilledWaveformSegment(
        in context: inout GraphicsContext,
        range: ClosedRange<CGFloat>,
        bars: [Float],
        barWidth: CGFloat,
        midY: CGFloat,
        maxBarHeight: CGFloat,
        fillColor: Color
    ) {
        let startX = max(0, range.lowerBound)
        let endX = min(range.upperBound, CGFloat(bars.count) * barWidth)
        guard endX > startX else { return }

        let startIndex = max(0, Int(floor(startX / barWidth)))
        let endIndex = min(bars.count - 1, Int(floor((endX - 0.001) / barWidth)))
        guard startIndex <= endIndex else {
            drawSilentSegment(in: &context, startX: startX, endX: endX, midY: midY, fillColor: fillColor)
            return
        }

        func barHeight(at index: Int) -> CGFloat {
            max(minBarHeight, CGFloat(bars[index]) * maxBarHeight)
        }

        func barCenterX(at index: Int) -> CGFloat {
            CGFloat(index) * barWidth + barWidth * 0.5
        }

        var path = Path()
        path.move(to: CGPoint(x: startX, y: midY))

        for index in startIndex...endIndex {
            path.addLine(to: CGPoint(x: barCenterX(at: index), y: midY - barHeight(at: index)))
        }

        path.addLine(to: CGPoint(x: endX, y: midY))

        for index in stride(from: endIndex, through: startIndex, by: -1) {
            path.addLine(to: CGPoint(x: barCenterX(at: index), y: midY + barHeight(at: index)))
        }

        path.addLine(to: CGPoint(x: startX, y: midY))
        path.closeSubpath()
        context.fill(path, with: .color(fillColor))
    }

    private func drawSilentSegment(
        in context: inout GraphicsContext,
        startX: CGFloat,
        endX: CGFloat,
        midY: CGFloat,
        fillColor: Color
    ) {
        guard endX > startX else { return }

        let rect = CGRect(x: startX, y: midY - minBarHeight, width: endX - startX, height: minBarHeight * 2)
        context.fill(Path(rect), with: .color(fillColor))
    }
}
