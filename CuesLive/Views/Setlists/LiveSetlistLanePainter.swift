import CoreGraphics
import Foundation

/// Draws the visible part of the setlist strip's song lanes: background, section bands, measure
/// grid, the summed waveform and the played split. Labels and gestures stay in SwiftUI above it.
///
/// Like the editor's `TimelineLanePainter`, every frame is drawn synchronously from an overview
/// pyramid at the current offset and zoom, so scrolling or zooming never shows a blank or stale
/// lane. Columns are cached per song, so a scroll only computes what it exposes.
@MainActor
final class LiveSetlistLanePainter {
    struct Band: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let color: CGColor
        let cuedColor: CGColor
        let isCued: Bool
    }

    struct Song: Equatable {
        /// Setlist position, matching the scroll model's lanes.
        let index: Int
        let source: LiveSetlistWaveformSource
        let duration: TimeInterval
        let bands: [Band]
        let tempoChanges: [TempoChange]
        let timeSignatureChanges: [TimeSignatureChange]
        let showsMeasureGrid: Bool
        let isCurrent: Bool
    }

    struct Scene: Equatable {
        var songs: [Song] = []
        var cueFlashPhase = false
        var backgroundColor = CGColor(gray: 0, alpha: 1)
        var separatorColor = CGColor(gray: 1, alpha: 0.1)
        var accentColor = CGColor(gray: 1, alpha: 1)
    }

    /// Where things are this frame, in strip coordinates. Compared each display-link frame, so
    /// the canvas only redraws when something on it moved.
    struct Layout: Equatable {
        var origin: CGPoint = .zero
        var lanes: [Int: CGRect] = [:]
        /// Strip x of the playhead, snapped to device pixels.
        var playheadX: CGFloat?
    }

    /// Everything that decides a song's columns.
    private struct LaneGeometry: Equatable {
        let width: CGFloat
        let scale: CGFloat
        let sourceKey: String
    }

    private static let cornerRadius = AppRadius.md
    private static let borderColor = CGColor(gray: 1, alpha: 0.08)
    private static let loadingColor = CGColor(gray: 1, alpha: 0.25)
    static let gridInset: CGFloat = 8

    private(set) var scene = Scene()
    private(set) var layout = Layout()
    /// Device pixels per point.
    var scale: CGFloat = 2
    /// Asks the view to draw again, when a waveform arrives.
    var onNeedsDisplay: () -> Void = {}

    /// Summed pyramid per source key. An empty overview means the song has no audio to show.
    private var overviews: [String: WaveformOverview] = [:]
    /// Last pyramid each lane drew, kept while an edited song's new one loads.
    private var shownOverviews: [Int: (key: String, overview: WaveformOverview)] = [:]
    private var loadingKeys: Set<String> = []
    private let columnCache = WaveformColumnCache<Int, LaneGeometry>()

    /// Returns `true` when the scene changed and needs drawing.
    func update(_ scene: Scene) -> Bool {
        guard scene != self.scene else { return false }
        self.scene = scene
        requestOverviews()
        return true
    }

    /// Returns `true` when the lanes, the offset or the playhead moved on screen.
    func update(from model: LiveSetlistScrollModel, origin: CGPoint) -> Bool {
        var lanes: [Int: CGRect] = [:]
        for song in scene.songs {
            lanes[song.index] = model.lane(at: song.index)?.frame
        }
        let layout = Layout(
            origin: origin,
            lanes: lanes,
            playheadX: model.playheadX.map { ($0 * scale).rounded() / scale }
        )
        guard layout != self.layout else { return false }
        self.layout = layout
        return true
    }

    /// Draws `rect`, in view coordinates.
    func draw(in context: CGContext, rect: CGRect) {
        columnCache.beginPass()
        for song in scene.songs {
            guard let frame = layout.lanes[song.index] else { continue }
            let laneRect = frame.offsetBy(dx: -layout.origin.x, dy: -layout.origin.y)
            let shown = laneRect.intersection(rect)
            guard !shown.isNull, shown.width > 0, shown.height > 0 else { continue }
            draw(song, in: laneRect, shown: shown, context: context)
        }
        columnCache.endPass()
    }

    // MARK: - Lane

    private func draw(_ song: Song, in lane: CGRect, shown: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        if !song.isCurrent {
            context.setAlpha(LiveSetlistWaveformMetrics.nonCurrentLaneOpacity)
            context.beginTransparencyLayer(in: shown, auxiliaryInfo: nil)
        }
        let outline = CGPath(
            roundedRect: lane,
            cornerWidth: Self.cornerRadius,
            cornerHeight: Self.cornerRadius,
            transform: nil
        )
        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.clip(to: shown)

        context.setFillColor(scene.backgroundColor)
        context.fill(shown)
        drawBands(song, in: lane, shown: shown, context: context)
        if song.showsMeasureGrid {
            drawMeasureGrid(song, in: lane, shown: shown, context: context)
        }
        drawWaveform(song, in: lane, shown: shown, context: context)
        context.restoreGState()

        context.addPath(outline)
        context.setStrokeColor(Self.borderColor)
        context.setLineWidth(0.5)
        context.strokePath()
        if !song.isCurrent {
            context.endTransparencyLayer()
        }
    }

    private func drawWaveform(_ song: Song, in lane: CGRect, shown: CGRect, context: CGContext) {
        guard song.source.hasAudio else { return }
        guard let (key, overview) = overview(for: song) else {
            context.setFillColor(Self.loadingColor)
            context.fill(CGRect(x: shown.minX, y: lane.midY - 1, width: shown.width, height: 2))
            return
        }
        guard overview.sampleCount > 0, lane.width > 0 else { return }

        let framesPerPoint = Double(overview.sampleCount) / Double(lane.width)
        let step = framesPerPoint / Double(scale)
        let overlap = max(0, framesPerPoint - step)
        let laneColumns = Int(ceil(lane.width * scale))
        let first = max(0, Int(floor((shown.minX - lane.minX) * scale)))
        let last = min(laneColumns, Int(ceil((shown.maxX - lane.minX) * scale)))
        guard first < last else { return }

        let scale = scale
        let paths = columnCache.paths(
            key: song.index,
            geometry: LaneGeometry(width: lane.width, scale: scale, sourceKey: key),
            scale: scale,
            channelCount: 1,
            columns: first..<last,
            half: lane.height * WaveformColumnGeometry.amplitudeFraction,
            gain: 1
        ) { range in
            // Each column is centered on its pixel, and the window reaches one point into its neighbours.
            let start = Double(range.lowerBound) / Double(scale) * framesPerPoint - overlap * 0.5
            return [overview.columns(start: start, step: step, overlap: overlap, count: range.count)]
        }
        let envelope = CGMutablePath()
        for path in paths.first ?? [] {
            envelope.addPath(path, transform: CGAffineTransform(translationX: lane.minX, y: lane.midY))
        }

        guard song.isCurrent, let playheadX = layout.playheadX.map({ $0 - layout.origin.x }) else {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.addPath(envelope)
            context.fillPath()
            return
        }
        // Draw each side once, so the played alpha replaces the unplayed one instead of stacking.
        let split = min(max(playheadX, lane.minX), lane.maxX)
        fill(envelope, in: CGRect(x: lane.minX, y: lane.minY, width: split - lane.minX, height: lane.height),
             alpha: LiveSetlistWaveformMetrics.waveformPlayedOpacity, context: context)
        fill(envelope, in: CGRect(x: split, y: lane.minY, width: lane.maxX - split, height: lane.height),
             alpha: LiveSetlistWaveformMetrics.waveformUnplayedOpacity, context: context)
    }

    private func fill(_ path: CGPath, in rect: CGRect, alpha: CGFloat, context: CGContext) {
        guard rect.width > 0 else { return }
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(CGColor(gray: 1, alpha: alpha))
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Loading

    private func overview(for song: Song) -> (key: String, overview: WaveformOverview)? {
        guard let overview = overviews[song.source.key] else {
            return shownOverviews[song.index]
        }
        shownOverviews[song.index] = (song.source.key, overview)
        return (song.source.key, overview)
    }

    /// Loads each song's summed pyramid once, then draws again.
    private func requestOverviews() {
        let keys = Set(scene.songs.map(\.source.key))
        overviews = overviews.filter { keys.contains($0.key) }
        let indices = Set(scene.songs.map(\.index))
        shownOverviews = shownOverviews.filter { indices.contains($0.key) }
        for song in scene.songs where song.source.hasAudio {
            let key = song.source.key
            guard overviews[key] == nil, !loadingKeys.contains(key) else { continue }
            loadingKeys.insert(key)
            let source = song.source
            Task { [weak self] in
                let overview = await source.loadOverview()
                guard let self else { return }
                loadingKeys.remove(key)
                guard scene.songs.contains(where: { $0.source.key == key }) else { return }
                overviews[key] = overview
                onNeedsDisplay()
            }
        }
    }
}
