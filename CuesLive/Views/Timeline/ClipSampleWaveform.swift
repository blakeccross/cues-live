import SwiftUI

/// One band per channel. Zoomed out, each pixel column is the real min and max in that window.
/// Zoomed to about a sample per pixel, the column is replaced by the samples themselves.
struct ClipSampleWaveform: View {
    let fileURL: URL
    let overview: WaveformFileOverview
    let sourceStart: TimeInterval
    let sourceDuration: TimeInterval
    /// The clip's x origin in timeline-content coordinates.
    let contentX: CGFloat
    let clipWidth: CGFloat
    let linearGain: Float
    let showsBaseline: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.timelineScrollModel) private var scrollModel
    @State private var sampleStrips: [[Float]] = []
    @State private var sampleOrigin: Int = 0

    var body: some View {
        let visibleContentX = scrollModel?.paintedRange
        Canvas { context, size in
            draw(in: &context, size: size, visibleContentX: visibleContentX)
        }
        .task(id: sampleTaskID(visibleContentX: visibleContentX)) {
            await loadSamplesIfNeeded(visibleContentX: visibleContentX)
        }
    }

    private var scale: CGFloat { max(displayScale, 1) }

    private var sourceFrames: Double {
        max(0, sourceDuration) * overview.sampleRate
    }

    private func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        visibleContentX: ClosedRange<CGFloat>?
    ) {
        let channels = max(overview.channels.count, 1)
        let bandHeight = size.height / CGFloat(channels)
        for index in 0..<channels {
            let band = CGRect(x: 0, y: CGFloat(index) * bandHeight, width: size.width, height: bandHeight)
            let peaks = index < overview.channels.count ? overview.channels[index] : nil
            let samples = index < sampleStrips.count ? sampleStrips[index] : []
            drawChannel(
                peaks,
                samples: samples,
                in: band,
                context: &context,
                clipWidth: size.width,
                visibleContentX: visibleContentX
            )
        }
    }

    private func drawChannel(
        _ peaks: WaveformOverview?,
        samples: [Float],
        in band: CGRect,
        context: inout GraphicsContext,
        clipWidth: CGFloat,
        visibleContentX: ClosedRange<CGFloat>?
    ) {
        guard clipWidth > 0, band.height > 0, overview.sampleRate > 0, sourceFrames > 0 else {
            if showsBaseline { strokeBaseline(in: band, context: &context) }
            return
        }
        let window = visibleWindow(clipWidth: clipWidth, visibleContentX: visibleContentX)
        let framesPerPoint = sourceFrames / Double(clipWidth)
        let step = framesPerPoint / Double(scale)
        let overlap = max(0, framesPerPoint - step)
        let origin = sourceStart * overview.sampleRate
        let pixelStart = Int(floor(window.lower * scale))
        let pixelEnd = Int(ceil(window.upper * scale))
        let count = max(0, pixelEnd - pixelStart)
        // Each column is centered on its pixel, and the window reaches one point into its neighbours.
        let windowStart = origin + Double(pixelStart) / Double(scale) * framesPerPoint - overlap * 0.5
        let half = band.height * WaveformColumnGeometry.amplitudeFraction
        let centerY = band.midY
        let color = Color.white.opacity(0.55)

        if samples.count > 1, step <= 1 {
            var path = Path()
            var started = false
            for index in samples.indices {
                let frame = Double(sampleOrigin + index)
                let x = CGFloat((frame - origin) / sourceFrames) * clipWidth
                guard x >= window.lower - 1, x <= window.upper + 1 else { continue }
                let y = centerY - CGFloat(clamp(scaled(samples[index]))) * half
                let point = CGPoint(x: x, y: y)
                if started {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
            }
            context.stroke(path, with: .color(color), lineWidth: max(1 / scale, 0.5))
            return
        }

        if samples.count > 1, let drawn = WaveformOverview.sampleColumns(
            samples: samples,
            origin: sampleOrigin,
            fileEnd: overview.channels.first?.sampleCount ?? samples.count,
            windowStart: windowStart,
            step: step,
            overlap: overlap,
            count: count
        ) {
            fillColumns(scaled(drawn), pixelStart: pixelStart, columnWidth: 1 / scale, centerY: centerY, half: half, color: color, context: &context)
            return
        }

        guard let peaks else {
            if showsBaseline { strokeBaseline(in: band, context: &context) }
            return
        }
        guard count > 0 else { return }
        let columns = peaks.columns(start: windowStart, step: step, overlap: overlap, count: count)
        fillColumns(scaled(columns), pixelStart: pixelStart, columnWidth: 1 / scale, centerY: centerY, half: half, color: color, context: &context)
    }

    private func fillColumns(
        _ columns: [(Float, Float)?],
        pixelStart: Int,
        columnWidth: CGFloat,
        centerY: CGFloat,
        half: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        var run: [WaveformColumnSpan] = []
        var runStart = 0

        func flush() {
            guard !run.isEmpty else { return }
            let path = Path(WaveformColumnGeometry.envelopePath(
                columns: run,
                originX: CGFloat(pixelStart + runStart) * columnWidth,
                columnWidth: columnWidth,
                centerY: centerY,
                half: half
            ))
            context.fill(path, with: .color(color))
            run.removeAll(keepingCapacity: true)
        }

        for (index, column) in columns.enumerated() {
            if let column {
                if run.isEmpty { runStart = index }
                run.append(WaveformColumnGeometry.thicken(
                    min: column.0,
                    max: column.1,
                    half: half,
                    scale: scale
                ))
            } else {
                flush()
            }
        }
        flush()
    }

    private func visibleWindow(
        clipWidth: CGFloat,
        visibleContentX: ClosedRange<CGFloat>?
    ) -> (lower: CGFloat, upper: CGFloat) {
        guard let visible = visibleContentX else { return (0, clipWidth) }
        let lower = max(0, visible.lowerBound - contentX)
        let upper = min(clipWidth, visible.upperBound - contentX)
        guard upper > lower else { return (0, 0) }
        return (lower, upper)
    }

    /// The frames of the file to load samples for, or `nil` while zoomed out far enough to use peaks.
    private func sampleRange(visibleContentX: ClosedRange<CGFloat>?) -> (first: Int, last: Int)? {
        guard overview.sampleRate > 0, sourceFrames > 1, clipWidth > 1 else { return nil }
        let window = visibleWindow(clipWidth: clipWidth, visibleContentX: visibleContentX)
        guard window.upper > window.lower else { return nil }
        let origin = sourceStart * overview.sampleRate
        let framesPerPoint = sourceFrames / Double(clipWidth)
        let pad = Int(ceil(framesPerPoint)) + 2
        let first = max(0, Int(floor(origin + Double(window.lower) * framesPerPoint)) - pad)
        let last = Int(ceil(origin + Double(window.upper) * framesPerPoint)) + pad
        guard last > first, last - first <= 200_000 else { return nil }
        return (first, last)
    }

    private func sampleTaskID(visibleContentX: ClosedRange<CGFloat>?) -> String {
        guard let range = sampleRange(visibleContentX: visibleContentX) else { return "peaks" }
        return "samples|\(fileURL.path)|\(range.first)|\(range.last)"
    }

    private func loadSamplesIfNeeded(visibleContentX: ClosedRange<CGFloat>?) async {
        guard let range = sampleRange(visibleContentX: visibleContentX) else {
            sampleStrips = []
            return
        }
        let start = max(0, range.first - 1)
        let count = min(range.last - start + 2, 200_000)
        let channelCount = overview.channels.count
        let url = fileURL
        let strips = await Task.detached(priority: .utility) {
            (0..<channelCount).map { channel in
                WaveformOverviewBuilder.samples(from: url, channel: channel, startFrame: start, count: count)
            }
        }.value
        // The read can't be cancelled; drop it if a newer window or file has taken over.
        guard !Task.isCancelled else { return }
        sampleOrigin = start
        sampleStrips = strips
    }

    private func strokeBaseline(in band: CGRect, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: band.minX, y: band.midY))
        path.addLine(to: CGPoint(x: band.maxX, y: band.midY))
        context.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
    }

    private func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value))
    }

    private func scaled(_ sample: Float) -> Float {
        linearGain == 1 ? sample : sample * linearGain
    }

    private func scaled(_ columns: [(Float, Float)?]) -> [(Float, Float)?] {
        guard linearGain != 1 else { return columns }
        return columns.map { column in
            guard let column else { return nil }
            return (clamp(column.0 * linearGain), clamp(column.1 * linearGain))
        }
    }
}
