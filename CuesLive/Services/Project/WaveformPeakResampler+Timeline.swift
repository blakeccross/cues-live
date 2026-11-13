import Foundation

extension WaveformPeakResampler {
    /// One track as it plays: its file's overview, read through its own clips.
    struct TimelineTrack: Sendable {
        let overview: WaveformFileOverview
        let clips: [TrackClip]
    }

    /// Sums every track's clips onto one timeline, the way the engine plays them: each clip reads
    /// its own stretch of its file at its own rate and gain, and audio a clip trims away is not
    /// drawn. Columns, channels and tracks add like `summedMinMax`, and the result is scaled so
    /// the loudest excursion fills the lane.
    static func timelineSummedMinMax(
        tracks: [TimelineTrack],
        timelineDuration: TimeInterval,
        columnsPerSecond: Double = summedColumnsPerSecond
    ) -> WaveformMinMax {
        guard timelineDuration > 0 else { return .empty }
        let wanted = Int((timelineDuration * columnsPerSecond).rounded(.up))
        let count = min(maximumSummedColumns, max(1, wanted))
        let columnDuration = timelineDuration / Double(count)
        var sum = WaveformMinMax(
            mins: [Float](repeating: 0, count: count),
            maxes: [Float](repeating: 0, count: count)
        )

        for track in tracks where track.overview.sampleRate > 0 {
            for clip in track.clips where clip.duration > 0 {
                for channel in track.overview.channels {
                    add(
                        clip,
                        of: channel,
                        sampleRate: track.overview.sampleRate,
                        columnDuration: columnDuration,
                        into: &sum
                    )
                }
            }
        }
        return normalized(sum)
    }

    /// Adds one channel of one clip. Columns wholly inside the clip are read as a run; the two
    /// it only partly covers read just the covered part, so a trim edge stays sharp.
    private static func add(
        _ clip: TrackClip,
        of channel: WaveformOverview,
        sampleRate: Double,
        columnDuration: TimeInterval,
        into sum: inout WaveformMinMax
    ) {
        let count = sum.count
        let first = max(0, Int(floor(clip.timelineStartSeconds / columnDuration)))
        let last = min(count, Int(ceil(clip.timelineEndSeconds / columnDuration)))
        guard first < last else { return }
        let gain = clip.linearGain
        let sample = { (time: TimeInterval) in clip.sourceTime(atTimeline: time) * sampleRate }

        func accumulate(_ column: Int, _ range: (Float, Float)?) {
            guard let range else { return }
            sum.mins[column] += range.0 * gain
            sum.maxes[column] += range.1 * gain
        }

        let interiorStart = Int(ceil(clip.timelineStartSeconds / columnDuration))
        let interiorEnd = min(last, Int(floor(clip.timelineEndSeconds / columnDuration)))
        if interiorStart < interiorEnd {
            let ranges = channel.columns(
                start: sample(Double(interiorStart) * columnDuration),
                step: columnDuration * clip.playbackRate * sampleRate,
                count: interiorEnd - interiorStart
            )
            for (offset, range) in ranges.enumerated() {
                accumulate(interiorStart + offset, range)
            }
        }
        for column in Set([first, last - 1]) where column < interiorStart || column >= interiorEnd {
            let start = max(Double(column) * columnDuration, clip.timelineStartSeconds)
            let end = min(Double(column + 1) * columnDuration, clip.timelineEndSeconds)
            guard end > start else { continue }
            let from = sample(start)
            let to = sample(end)
            accumulate(column, channel.columns(start: from, step: max(to - from, .ulpOfOne), count: 1).first ?? nil)
        }
    }

    private static func normalized(_ series: WaveformMinMax) -> WaveformMinMax {
        var peak: Float = 0
        for index in 0..<series.count {
            peak = max(peak, abs(series.mins[index]), abs(series.maxes[index]))
        }
        guard peak > 0 else { return series }
        return WaveformMinMax(mins: series.mins.map { $0 / peak }, maxes: series.maxes.map { $0 / peak })
    }
}
