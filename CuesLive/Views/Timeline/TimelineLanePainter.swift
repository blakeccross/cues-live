import CoreGraphics
import Foundation

/// Draws the visible part of the editor's audio lanes: the lane background, each clip's body
/// and its waveform. Clip headers, borders and gestures stay in SwiftUI above it.
///
/// Like SoundCraft and other DAWs, every frame is drawn synchronously from the overview
/// pyramid at the current offset and zoom, so scrolling or zooming never shows a blank or
/// stale waveform. Columns are cached per clip, so a scroll only computes what it exposes.
@MainActor
final class TimelineLanePainter {
    struct Lane: Equatable {
        let originY: CGFloat
        let height: CGFloat
        let fileURL: URL
        let bodyColor: CGColor
        let clips: [TimelineCanvasClip]
    }

    struct Scene: Equatable {
        var lanes: [Lane] = []
        var duration: TimeInterval = 1
        var contentWidth: CGFloat = 1
        var backgroundColor = CGColor(gray: 0, alpha: 1)
        /// `false` until the song has loaded, so opening the editor does not queue every file.
        var loadsWaveforms = false
    }

    /// The part of one clip being drawn, in content points.
    /// Everything that decides a clip's columns.
    private struct ClipGeometry: Equatable {
        let fileURL: URL
        let startX: CGFloat
        let clipWidth: CGFloat
        let sourceStart: TimeInterval
        let sourceDuration: TimeInterval
        let scale: CGFloat
        let channelCount: Int
        /// Identity of the raw samples the columns were taken from, or 0 for the pyramid.
        let sampleGeneration: Int
    }

    private struct ClipSpan {
        let clip: TimelineCanvasClip
        let startX: CGFloat
        let width: CGFloat
        let visibleX: ClosedRange<CGFloat>
    }

    private static let waveformColor = CGColor(gray: 1, alpha: 0.55)
    private static let baselineColor = CGColor(gray: 1, alpha: 0.35)

    private(set) var scene = Scene()
    /// Horizontal scroll offset in content points. View x is content x minus the offset.
    var offset: CGFloat = 0
    var scale: CGFloat = 2
    /// Asks the view to draw again, when a waveform or a sample window arrives.
    var onNeedsDisplay: () -> Void = {}

    private var overviews: [URL: WaveformFileOverview] = [:]
    private var loadingOverviews: Set<URL> = []
    private let columnCache = WaveformColumnCache<UUID, ClipGeometry>()
    private let sampleWindows = ClipSampleWindowStore()

    init() {
        sampleWindows.onLoad = { [weak self] in
            self?.onNeedsDisplay()
        }
    }

    /// Returns `true` when the scene changed and needs drawing.
    func update(_ scene: Scene) -> Bool {
        guard scene != self.scene else { return false }
        self.scene = scene
        requestOverviews()
        return true
    }

    /// Draws `rect`, in view coordinates.
    func draw(in context: CGContext, rect: CGRect) {
        context.setFillColor(scene.backgroundColor)
        context.fill(rect)
        columnCache.beginPass()
        var drawn: Set<UUID> = []
        for lane in scene.lanes where lane.originY < rect.maxY && lane.originY + lane.height > rect.minY {
            for clip in lane.clips where draw(clip, in: lane, rect: rect, context: context) {
                drawn.insert(clip.id)
            }
        }
        columnCache.endPass()
        sampleWindows.retain(drawn)
    }

    private func x(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: scene.duration, contentWidth: scene.contentWidth)
    }

    /// Body and waveform of one clip. Returns `false` when the clip is off screen.
    private func draw(_ clip: TimelineCanvasClip, in lane: Lane, rect: CGRect, context: CGContext) -> Bool {
        let startX = x(for: clip.timelineStart)
        let endX = x(for: clip.timelineEnd)
        guard endX > startX, endX - offset > rect.minX, startX - offset < rect.maxX else { return false }

        let clipHeight = max(0, lane.height - TimelineLayout.laneDividerHeight)
        let body = CGRect(x: startX - offset, y: lane.originY, width: endX - startX, height: clipHeight)
        context.setFillColor(lane.bodyColor)
        context.fill(body.intersection(rect))

        let band = CGRect(
            x: body.minX,
            y: lane.originY + TimelineLayout.clipHeaderHeight,
            width: body.width,
            height: clipHeight - TimelineLayout.clipHeaderHeight
        )
        let shown = band.intersection(rect)
        guard band.height > 2, !shown.isNull, shown.width > 0 else { return true }

        context.saveGState()
        context.clip(to: shown)
        let span = ClipSpan(
            clip: clip,
            startX: startX,
            width: endX - startX,
            visibleX: (shown.minX + offset)...(shown.maxX + offset)
        )
        drawWaveform(span, fileURL: lane.fileURL, band: band, context: context)
        context.restoreGState()
        return true
    }

    private func drawWaveform(_ span: ClipSpan, fileURL: URL, band: CGRect, context: CGContext) {
        guard let overview = overviews[fileURL],
              let firstChannel = overview.channels.first,
              overview.sampleRate > 0,
              span.clip.sourceDuration > 0
        else {
            strokeBaseline(in: band, context: context)
            return
        }
        let channelCount = overview.channels.count
        let framesPerPoint = span.clip.sourceDuration * overview.sampleRate / Double(span.width)
        let origin = span.clip.sourceStart * overview.sampleRate
        let firstFrame = Int(floor(origin + Double(span.visibleX.lowerBound - span.startX) * framesPerPoint)) - 2
        let endFrame = Int(ceil(origin + Double(span.visibleX.upperBound - span.startX) * framesPerPoint)) + 2
        let frames = max(0, firstFrame)..<max(0, min(firstChannel.sampleCount, endFrame))
        let window = sampleWindows.window(
            for: span.clip.id,
            fileURL: fileURL,
            channelCount: channelCount,
            frames: frames
        )
        let bandHeight = band.height / CGFloat(channelCount)

        // A sample per device pixel or closer: the samples themselves, joined by a line.
        if framesPerPoint / Double(scale) <= 1, let window {
            for channel in 0..<min(channelCount, window.channels.count) {
                let channelBand = CGRect(
                    x: band.minX,
                    y: band.minY + CGFloat(channel) * bandHeight,
                    width: band.width,
                    height: bandHeight
                )
                strokeSamples(
                    window,
                    channel: channel,
                    frames: frames,
                    span: span,
                    origin: origin,
                    framesPerPoint: framesPerPoint,
                    band: channelBand,
                    context: context
                )
            }
            return
        }

        let geometry = ClipGeometry(
            fileURL: fileURL,
            startX: span.startX,
            clipWidth: span.width,
            sourceStart: span.clip.sourceStart,
            sourceDuration: span.clip.sourceDuration,
            scale: scale,
            channelCount: channelCount,
            sampleGeneration: window?.generation ?? 0
        )
        let columns = Int(floor(span.visibleX.lowerBound * scale))..<Int(ceil(span.visibleX.upperBound * scale))
        let paths = columnCache.paths(
            key: span.clip.id,
            geometry: geometry,
            scale: scale,
            channelCount: channelCount,
            columns: columns,
            half: bandHeight * WaveformColumnGeometry.amplitudeFraction,
            gain: span.clip.linearGain
        ) { range in
            Self.columns(
                range,
                span: span,
                overview: overview,
                window: window,
                origin: origin,
                framesPerPoint: framesPerPoint,
                scale: scale
            )
        }

        context.setFillColor(Self.waveformColor)
        for (channel, chunks) in paths.enumerated() {
            context.saveGState()
            context.translateBy(x: -offset, y: band.minY + (CGFloat(channel) + 0.5) * bandHeight)
            for path in chunks {
                context.addPath(path)
            }
            context.fillPath()
            context.restoreGState()
        }
    }

    /// Min and max of each device-pixel column in `range`, per channel. Columns outside the clip are `nil`.
    private static func columns(
        _ range: Range<Int>,
        span: ClipSpan,
        overview: WaveformFileOverview,
        window: ClipSampleWindowStore.Window?,
        origin: Double,
        framesPerPoint: Double,
        scale: CGFloat
    ) -> [[(Float, Float)?]] {
        let step = framesPerPoint / Double(scale)
        let overlap = max(0, framesPerPoint - step)
        let lower = max(range.lowerBound, Int(floor(span.startX * scale)))
        let upper = min(range.upperBound, Int(ceil((span.startX + span.width) * scale)))
        let empty = [(Float, Float)?](repeating: nil, count: range.count)
        guard lower < upper else { return Array(repeating: empty, count: overview.channels.count) }

        // Each column is centered on its pixel, and the window reaches one point into its neighbours.
        let windowStart = origin + (Double(lower) / Double(scale) - Double(span.startX)) * framesPerPoint - overlap * 0.5
        let count = upper - lower
        let leading = [(Float, Float)?](repeating: nil, count: lower - range.lowerBound)
        let trailing = [(Float, Float)?](repeating: nil, count: range.upperBound - upper)
        return overview.channels.enumerated().map { channel, pyramid in
            var inside: [(Float, Float)?]?
            if let window, channel < window.channels.count {
                inside = WaveformOverview.sampleColumns(
                    samples: window.channels[channel],
                    origin: window.origin,
                    fileEnd: pyramid.sampleCount,
                    windowStart: windowStart,
                    step: step,
                    overlap: overlap,
                    count: count
                )
            }
            let columns = inside ?? pyramid.columns(start: windowStart, step: step, overlap: overlap, count: count)
            return leading + columns + trailing
        }
    }

    private func strokeSamples(
        _ window: ClipSampleWindowStore.Window,
        channel: Int,
        frames: Range<Int>,
        span: ClipSpan,
        origin: Double,
        framesPerPoint: Double,
        band: CGRect,
        context: CGContext
    ) {
        let samples = window.channels[channel]
        let half = band.height * WaveformColumnGeometry.amplitudeFraction
        let path = CGMutablePath()
        for frame in frames {
            let index = frame - window.origin
            guard samples.indices.contains(index) else { continue }
            let x = span.startX + CGFloat((Double(frame) - origin) / framesPerPoint) - offset
            let value = WaveformColumnGeometry.clampedAmplitude(samples[index] * span.clip.linearGain)
            let point = CGPoint(x: x, y: band.midY - CGFloat(value) * half)
            if path.isEmpty {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.setStrokeColor(Self.waveformColor)
        context.setLineWidth(max(1 / scale, 0.5))
        context.addPath(path)
        context.strokePath()
    }

    private func strokeBaseline(in band: CGRect, context: CGContext) {
        context.setStrokeColor(Self.baselineColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: band.minX, y: band.midY))
        context.addLine(to: CGPoint(x: band.maxX, y: band.midY))
        context.strokePath()
    }

    /// Loads the overview pyramid of each lane's file once, then draws again.
    private func requestOverviews() {
        for url in Set(scene.lanes.map(\.fileURL)) where overviews[url] == nil && !loadingOverviews.contains(url) {
            if let cached = WaveformCache.shared.cachedOverview(for: url) {
                overviews[url] = cached
                continue
            }
            guard scene.loadsWaveforms else { continue }
            loadingOverviews.insert(url)
            Task { [weak self] in
                let overview = await WaveformCache.shared.overview(for: url)
                guard let self else { return }
                loadingOverviews.remove(url)
                overviews[url] = overview
                onNeedsDisplay()
            }
        }
    }
}
