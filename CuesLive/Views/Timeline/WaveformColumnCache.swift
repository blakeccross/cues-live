import CoreGraphics
import Foundation

/// Envelope paths for the clips on screen, built a chunk of device-pixel columns at a time.
///
/// Columns sit on the timeline content's pixel grid, so a scroll reuses every chunk already
/// built and computes only the ones it exposes. Columns are kept while a clip's geometry holds;
/// the paths are rebuilt from them when only the gain or the lane height changes.
@MainActor
final class WaveformColumnCache {
    static let chunkColumns = 256
    /// Chunks kept on each side of the ones drawn, so scrolling back and forth reuses them.
    private static let retainedChunks = 8

    /// Everything that decides a clip's columns.
    struct Geometry: Equatable {
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

    /// Everything else a path depends on.
    private struct PathStyle: Equatable {
        let half: CGFloat
        let gain: Float
    }

    private struct Chunk {
        /// Per channel. `nil` where a column misses the clip or the file.
        let columns: [[(Float, Float)?]]
        var style: PathStyle?
        var paths: [CGPath] = []
    }

    private struct Entry {
        let geometry: Geometry
        var chunks: [Int: Chunk] = [:]
    }

    private var entries: [UUID: Entry] = [:]
    private var drawnThisPass: Set<UUID> = []

    func beginPass() {
        drawnThisPass.removeAll(keepingCapacity: true)
    }

    /// Forgets clips that were not drawn in the pass just finished.
    func endPass() {
        entries = entries.filter { drawnThisPass.contains($0.key) }
    }

    /// One path per channel and chunk covering `columns`, in content x with y centered on 0.
    /// `compute` returns the columns of a range, per channel.
    func paths(
        clipID: UUID,
        geometry: Geometry,
        columns: Range<Int>,
        half: CGFloat,
        gain: Float,
        compute: (Range<Int>) -> [[(Float, Float)?]]
    ) -> [[CGPath]] {
        drawnThisPass.insert(clipID)
        var entry = entries[clipID].flatMap { $0.geometry == geometry ? $0 : nil } ?? Entry(geometry: geometry)
        let style = PathStyle(half: half, gain: gain)
        var result = Array(repeating: [CGPath](), count: geometry.channelCount)
        guard !columns.isEmpty else { return result }

        let first = Self.chunkIndex(of: columns.lowerBound)
        let last = Self.chunkIndex(of: columns.upperBound - 1)
        for index in first...last {
            var chunk = entry.chunks[index] ?? Chunk(columns: compute(Self.columnRange(ofChunk: index)))
            if chunk.style != style {
                chunk.paths = chunk.columns.map { channel in
                    Self.envelope(channel, firstColumn: index * Self.chunkColumns, style: style, scale: geometry.scale)
                }
                chunk.style = style
            }
            entry.chunks[index] = chunk
            for (channel, path) in chunk.paths.enumerated() where channel < result.count {
                result[channel].append(path)
            }
        }
        let keep = (first - Self.retainedChunks)...(last + Self.retainedChunks)
        entry.chunks = entry.chunks.filter { keep.contains($0.key) }
        entries[clipID] = entry
        return result
    }

    private static func chunkIndex(of column: Int) -> Int {
        Int((Double(column) / Double(chunkColumns)).rounded(.down))
    }

    private static func columnRange(ofChunk index: Int) -> Range<Int> {
        (index * chunkColumns)..<((index + 1) * chunkColumns)
    }

    /// Runs of present columns, each closed into an envelope.
    private static func envelope(
        _ columns: [(Float, Float)?],
        firstColumn: Int,
        style: PathStyle,
        scale: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        let columnWidth = 1 / scale
        var run: [WaveformColumnSpan] = []
        var runStart = 0

        func flush() {
            guard !run.isEmpty else { return }
            path.addPath(WaveformColumnGeometry.envelopePath(
                columns: run,
                originX: CGFloat(firstColumn + runStart) * columnWidth,
                columnWidth: columnWidth,
                centerY: 0,
                half: style.half
            ))
            run.removeAll(keepingCapacity: true)
        }

        for (index, column) in columns.enumerated() {
            guard let column else {
                flush()
                continue
            }
            if run.isEmpty { runStart = index }
            run.append(WaveformColumnGeometry.thicken(
                min: scaled(column.0, gain: style.gain),
                max: scaled(column.1, gain: style.gain),
                half: style.half,
                scale: scale
            ))
        }
        flush()
        return path
    }

    private static func scaled(_ value: Float, gain: Float) -> Float {
        WaveformColumnGeometry.clampedAmplitude(gain == 1 ? value : value * gain)
    }
}
