import SwiftUI

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

    private let minBarHeight: CGFloat = 1.0
    private let voiceMemosMinBarHeight: CGFloat = 2.0

    var body: some View {
        let canvas = Canvas { context, size in
            drawWaveform(in: &context, size: size)
        }
        // `drawingGroup()` helps short static waveforms, but forces a huge Metal
        // offscreen while `playheadFraction` animates or when the lane is very wide.
        if usesDrawingGroup, playheadFraction == nil {
            canvas.drawingGroup()
        } else {
            canvas
        }
    }

    private func drawWaveform(in context: inout GraphicsContext, size: CGSize) {
        switch style {
        case .filledEnvelope:
            drawFilledEnvelopeWaveform(in: &context, size: size)
        case .voiceMemosBars:
            drawVoiceMemosBars(in: &context, size: size)
        }
    }

    private func drawFilledEnvelopeWaveform(in context: inout GraphicsContext, size: CGSize) {
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
        let activeColor = usesCustomFill ? fillColor : playedColor
        let inactiveColor = usesCustomFill ? fillColor.opacity(0.32) : unplayedColor
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
