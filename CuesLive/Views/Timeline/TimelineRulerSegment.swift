import Foundation

/// One stretch of the meter or tempo ruler, from a change to the next one or to the song's end,
/// with the value it shows.
struct TimelineRulerSegment<Marker> {
    let marker: Marker
    let startTime: TimeInterval
    let endTime: TimeInterval
    let label: String
}

extension TimelineRulerSegment where Marker == TimeSignatureChange {
    static func segments(
        timeSignatureChanges: [TimeSignatureChange],
        tempoChanges: [TempoChange],
        duration: TimeInterval
    ) -> [Self] {
        let markers = timeSignatureChanges.sortedByMeasure
        let starts = markers.map {
            MeasureTiming.timeAtStartOfMeasure(
                $0.startMeasure,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges
            )
        }
        return markers.enumerated().map { index, marker in
            TimelineRulerSegment(
                marker: marker,
                startTime: starts[index],
                endTime: index + 1 < starts.count ? starts[index + 1] : duration,
                label: marker.displayName
            )
        }
    }
}

extension TimelineRulerSegment where Marker == TempoChange {
    /// Narrower tempo segments leave their value out.
    static let minimumLabeledWidth: CGFloat = 28

    static func segments(
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        duration: TimeInterval
    ) -> [Self] {
        let markers = tempoChanges.sortedByMeasure
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let starts = markers.map { marker in
            timeline.seconds(atTick: TempoTimeline.tick(
                measure: marker.startMeasure,
                beatOffset: marker.beatOffset,
                timeSignatureChanges: timeSignatureChanges
            ))
        }
        return markers.enumerated().map { index, marker in
            TimelineRulerSegment(
                marker: marker,
                startTime: starts[index],
                endTime: index + 1 < starts.count ? starts[index + 1] : duration,
                label: String(format: "%.0f", marker.bpm)
            )
        }
    }
}
