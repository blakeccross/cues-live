import Foundation

/// Empty measures the song editor shows past the end of a song, so there is room to extend it.
enum TimelineTrailingSpace {
    /// Share of the song's measure count added after its end.
    static let paddingFraction = 0.1
    /// Fewest measures the editor lays out, song plus padding.
    static let minimumMeasureCount = 58

    /// Timeline length the editor lays out for a song ending at `songDuration`: the song's measures,
    /// plus 10% of them rounded up, and never fewer than `minimumMeasureCount` measures in total.
    static func displayDuration(
        songDuration: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        let tempos = tempoChanges.isEmpty
            ? [TempoChange(startMeasure: 1, bpm: TempoChange.defaultBPM)]
            : tempoChanges
        let songMeasures = songDuration > 0
            ? MeasureTiming.measureIndex(
                at: max(0, songDuration - 0.001),
                tempoChanges: tempos,
                timeSignatureChanges: timeSignatureChanges
            )
            : 0
        let padding = Int((Double(songMeasures) * paddingFraction).rounded(.up))
        let measureCount = max(minimumMeasureCount, songMeasures + padding)
        let end = MeasureTiming.timeAtStartOfMeasure(
            measureCount + 1,
            tempoChanges: tempos,
            timeSignatureChanges: timeSignatureChanges
        )
        return max(songDuration, end)
    }
}
