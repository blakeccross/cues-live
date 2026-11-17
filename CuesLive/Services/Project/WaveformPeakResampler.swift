import Accelerate
import CoreGraphics
import Foundation

/// Min and max of a summed waveform, one pair per time bucket.
struct WaveformMinMax: Equatable, Sendable {
    var mins: [Float]
    var maxes: [Float]

    static let empty = WaveformMinMax(mins: [], maxes: [])

    var count: Int { min(mins.count, maxes.count) }
    var isEmpty: Bool { count == 0 }

    /// Magnitude peaks have no polarity. Mirror them so the column drawer still has a span.
    static func mirrored(_ peaks: [Float]) -> WaveformMinMax {
        WaveformMinMax(mins: peaks.map { -$0 }, maxes: peaks)
    }

    /// The series as an overview pyramid, so a zoomed-out lane reads coarse blocks instead of
    /// every column. Each column becomes one level-0 block, so column `i` spans overview
    /// positions `[i * WaveformOverview.block, (i + 1) * WaveformOverview.block)`.
    func overview() -> WaveformOverview {
        let level0 = (0..<count).map { WaveformOverview.Block(min: mins[$0], max: maxes[$0]) }
        return WaveformOverview(sampleCount: count * WaveformOverview.block, level0: level0)
    }
}

enum WaveformPeakResampler {
    /// How many summed min/max buckets to keep per second of audio.
    /// Denser than the setlist's sharpest zoom, so each pixel still covers real extrema.
    static let summedColumnsPerSecond: Double = 100
    /// Bounds memory for very long stems (~33 minutes at full density).
    static let maximumSummedColumns = 200_000

    /// Sums each file's min/max overview onto one timeline.
    /// Channels and files add, which is the outer bound of the mix: a column's min is the sum of
    /// the mins, and its max is the sum of the maxes. The result is scaled so the loudest
    /// excursion fills the lane, keeping the asymmetry of the sum.
    static func summedMinMax(
        from sources: [(overview: WaveformFileOverview, duration: TimeInterval)],
        columnsPerSecond: Double = summedColumnsPerSecond
    ) -> WaveformMinMax {
        let maxDuration = sources.map(\.duration).max() ?? 0
        guard maxDuration > 0 else { return .empty }

        let wanted = Int((maxDuration * columnsPerSecond).rounded(.up))
        let count = min(maximumSummedColumns, max(1, wanted))
        var mins = [Float](repeating: 0, count: count)
        var maxes = [Float](repeating: 0, count: count)

        for source in sources {
            guard source.duration > 0 else { continue }
            let fraction = min(1, source.duration / maxDuration)
            let fileColumns = min(count, max(1, Int((fraction * Double(count)).rounded(.up))))
            for channel in source.overview.channels {
                add(
                    channel,
                    fileColumns: fileColumns,
                    mins: &mins,
                    maxes: &maxes
                )
            }
        }

        var peak: Float = 0
        for index in 0..<count {
            peak = max(peak, abs(mins[index]), abs(maxes[index]))
        }
        guard peak > 0 else { return WaveformMinMax(mins: mins, maxes: maxes) }
        for index in 0..<count {
            mins[index] /= peak
            maxes[index] /= peak
        }
        return WaveformMinMax(mins: mins, maxes: maxes)
    }

    /// Lays a file-time min/max series onto the arrangement.
    /// Buckets that miss every clip stay silent. A bucket that crosses clips keeps the extrema
    /// of each piece it touches.
    static func timelineMinMax(
        from source: WaveformMinMax,
        fileDuration: TimeInterval,
        clips: [TrackClip],
        timelineDuration: TimeInterval
    ) -> WaveformMinMax {
        let count = source.count
        guard count > 0 else { return .empty }
        guard fileDuration > 0, !clips.isEmpty else { return source }

        let safeTimeline = max(timelineDuration, 0.001)
        let sorted = clips.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        var mins = [Float](repeating: 0, count: count)
        var maxes = [Float](repeating: 0, count: count)

        for index in 0..<count {
            let start = safeTimeline * Double(index) / Double(count)
            let end = safeTimeline * Double(index + 1) / Double(count)
            var low = Float.infinity
            var high = -Float.infinity
            for clip in sorted {
                if clip.timelineEndSeconds <= start { continue }
                if clip.timelineStartSeconds >= end { break }
                let overlapStart = max(start, clip.timelineStartSeconds)
                let overlapEnd = min(end, clip.timelineEndSeconds)
                guard overlapEnd > overlapStart else { continue }
                let sourceStart = clip.sourceTime(atTimeline: overlapStart)
                let sourceEnd = clip.sourceTime(atTimeline: overlapEnd)
                let from = min(max(0, Int(floor(sourceStart / fileDuration * Double(count)))), count - 1)
                let to = min(max(0, Int(ceil(sourceEnd / fileDuration * Double(count))) - 1), count - 1)
                guard from <= to else { continue }
                for sourceIndex in from...to {
                    low = min(low, source.mins[sourceIndex])
                    high = max(high, source.maxes[sourceIndex])
                }
            }
            if low <= high {
                mins[index] = low
                maxes[index] = high
            }
        }
        return WaveformMinMax(mins: mins, maxes: maxes)
    }

    /// Folds one channel's 32-sample blocks into `fileColumns` contiguous buckets.
    private static func add(
        _ channel: WaveformOverview,
        fileColumns: Int,
        mins: inout [Float],
        maxes: inout [Float]
    ) {
        guard channel.sampleCount > 0, fileColumns > 0,
              let level0 = channel.levels.first, !level0.isEmpty else { return }

        var blockIndex = 0
        let blockCount = level0.count
        let sampleCount = channel.sampleCount
        let columns = min(fileColumns, mins.count)
        for column in 0..<columns {
            let endSample = column == columns - 1
                ? sampleCount
                : min(sampleCount, Int((Double(column + 1) / Double(columns) * Double(sampleCount)).rounded(.up)))
            let endBlock = min(blockCount, (endSample + WaveformOverview.block - 1) / WaveformOverview.block)
            let stop = max(blockIndex, endBlock)
            var low = Float.infinity
            var high = -Float.infinity
            while blockIndex < stop {
                let block = level0[blockIndex]
                if block.min <= block.max {
                    low = min(low, block.min)
                    high = max(high, block.max)
                }
                blockIndex += 1
            }
            if low <= high {
                mins[column] += low
                maxes[column] += high
            }
        }
    }

    /// Collapses `peaks` into consecutive groups of `groupSize`, keeping each group's maximum.
    /// `groups` are group indices; ones that start past the end of `peaks` are omitted.
    static func groupedMaxima(
        of peaks: [Float],
        groupSize: Int,
        groups: ClosedRange<Int>
    ) -> [Float] {
        let size = max(1, groupSize)
        return groups.compactMap { group in
            let start = group * size
            guard start >= 0, start < peaks.count else { return nil }
            return peaks[start..<min(start + size, peaks.count)].max()
        }
    }
}
