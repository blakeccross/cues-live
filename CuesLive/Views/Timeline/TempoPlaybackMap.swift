import Foundation

/// Precomputed tempo segments for O(markers) playback integration on the audio thread.
struct TempoPlaybackMap: Sendable {
    struct Segment: Sendable {
        let sourceStart: TimeInterval
        let sourceEnd: TimeInterval
        let ratio: Double
    }

    let segments: [Segment]

    static let defaultMaxSourceTime: TimeInterval = 86_400

    static func build(
        tempoChanges: [TempoChange],
        referenceBPM: Double,
        timeSignatureChanges: [TimeSignatureChange],
        maxSourceTime: TimeInterval = defaultMaxSourceTime
    ) -> TempoPlaybackMap {
        guard referenceBPM > 0, !tempoChanges.isEmpty else {
            return TempoPlaybackMap(segments: [])
        }

        let markers = tempoChanges.sortedByMeasure
        let timeline = TempoTimeline(tempoChanges: markers, timeSignatureChanges: timeSignatureChanges)
        var segments: [Segment] = []

        for (index, marker) in markers.enumerated() {
            let startTick = TempoTimeline.tick(
                measure: marker.startMeasure,
                beatOffset: marker.beatOffset,
                timeSignatureChanges: timeSignatureChanges
            )
            let sourceStart = timeline.seconds(atTick: startTick)
            let sourceEnd: TimeInterval
            if index + 1 < markers.count {
                let next = markers[index + 1]
                let nextTick = TempoTimeline.tick(
                    measure: next.startMeasure,
                    beatOffset: next.beatOffset,
                    timeSignatureChanges: timeSignatureChanges
                )
                sourceEnd = timeline.seconds(atTick: nextTick)
            } else {
                sourceEnd = max(maxSourceTime, sourceStart + 1)
            }

            guard sourceEnd > sourceStart else { continue }
            segments.append(
                Segment(
                    sourceStart: sourceStart,
                    sourceEnd: sourceEnd,
                    ratio: marker.bpm / referenceBPM
                )
            )
        }

        return TempoPlaybackMap(segments: segments)
    }

    func sourceTimeAfterWallElapsed(from anchor: TimeInterval, wallElapsed: TimeInterval) -> TimeInterval {
        guard wallElapsed > 0, !segments.isEmpty else { return max(0, anchor) }

        var wall = wallElapsed
        var source = max(0, anchor)
        var segmentIndex = segmentIndex(for: source)

        while wall > 0.000_000_1, segmentIndex < segments.count {
            let segment = segments[segmentIndex]
            source = max(source, segment.sourceStart)

            let remainingSource = segment.sourceEnd - source
            guard remainingSource > 0 else {
                segmentIndex += 1
                continue
            }

            let wallForRemainder = remainingSource / segment.ratio
            if wall <= wallForRemainder + 0.000_000_1 {
                return min(segment.sourceEnd, source + wall * segment.ratio)
            }

            wall -= wallForRemainder
            source = segment.sourceEnd
            segmentIndex += 1
        }

        return source
    }

    /// Wall-clock seconds playback needs to advance from source time `start` to `end`.
    func wallElapsed(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        guard end > start else { return 0 }
        guard !segments.isEmpty else { return end - start }

        var wall: TimeInterval = 0
        for segment in segments {
            let lower = max(start, segment.sourceStart)
            let upper = min(end, segment.sourceEnd)
            if upper > lower {
                wall += (upper - lower) / segment.ratio
            }
        }
        return wall
    }

    func ratio(at sourceTime: TimeInterval) -> Double {
        guard !segments.isEmpty else { return 1.0 }
        let time = max(0, sourceTime)
        if let segment = segments.last(where: { time >= $0.sourceStart - 0.000_1 && time < $0.sourceEnd - 0.000_1 }) {
            return segment.ratio
        }
        return segments.last?.ratio ?? 1.0
    }

    private func segmentIndex(for sourceTime: TimeInterval) -> Int {
        guard !segments.isEmpty else { return 0 }
        for (index, segment) in segments.enumerated() {
            if sourceTime < segment.sourceEnd - 0.000_1 {
                return index
            }
        }
        return segments.count - 1
    }
}
