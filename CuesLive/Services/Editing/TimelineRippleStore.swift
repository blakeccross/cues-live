import Foundation

/// Ripple delete: removes a measure-aligned time span from the whole song and shifts
/// everything after it earlier to close the gap.
enum TimelineRippleStore {
    struct Result {
        /// Tracks left with no clips (their content fell entirely inside the deleted span).
        var emptiedTrackIDs: [UUID]
    }

    /// Removes measures `[startMeasure, endMeasure)` and collapses the gap across every timeline dimension.
    @discardableResult
    static func rippleDeleteMeasures(
        startMeasure: Int,
        endMeasure: Int,
        timeline: inout SongTimeline,
        tempoChanges: inout [TempoChange],
        timeSignatureChanges: inout [TimeSignatureChange],
        midiEvents: inout [MIDIEvent],
        defaultBPM: Double,
        defaultNumerator: Int,
        defaultDenominator: Int
    ) -> Result {
        guard endMeasure > startMeasure, startMeasure >= 1 else {
            return Result(emptiedTrackIDs: [])
        }

        let originalTempo = tempoChanges
        let originalTimeSignature = timeSignatureChanges

        let tStart = MeasureTiming.timeAtStartOfMeasure(
            startMeasure,
            tempoChanges: originalTempo,
            timeSignatureChanges: originalTimeSignature
        )
        let tEnd = MeasureTiming.timeAtStartOfMeasure(
            endMeasure,
            tempoChanges: originalTempo,
            timeSignatureChanges: originalTimeSignature
        )
        let removedMeasures = endMeasure - startMeasure
        guard tEnd > tStart else { return Result(emptiedTrackIDs: []) }

        let trackIDsBefore = Set(timeline.clips.map(\.trackID))
        ClipEditing.rippleDelete(from: tStart, to: tEnd, timeline: &timeline, midiEvents: &midiEvents)

        tempoChanges = rippledTempoChanges(
            originalTempo,
            startMeasure: startMeasure,
            endMeasure: endMeasure,
            removedMeasures: removedMeasures,
            defaultBPM: defaultBPM
        )
        timeSignatureChanges = rippledTimeSignatureChanges(
            originalTimeSignature,
            startMeasure: startMeasure,
            endMeasure: endMeasure,
            removedMeasures: removedMeasures,
            defaultNumerator: defaultNumerator,
            defaultDenominator: defaultDenominator
        )

        let trackIDsAfter = Set(timeline.clips.map(\.trackID))
        return Result(emptiedTrackIDs: trackIDsBefore.subtracting(trackIDsAfter).sorted { $0.uuidString < $1.uuidString })
    }

    // MARK: - Tempo / time signature

    private static func rippledTempoChanges(
        _ changes: [TempoChange],
        startMeasure: Int,
        endMeasure: Int,
        removedMeasures: Int,
        defaultBPM: Double
    ) -> [TempoChange] {
        var result = changes.filter { $0.startMeasure < startMeasure }

        // The measure that becomes the new `startMeasure` inherits the tempo active at `endMeasure`.
        if let boundary = changes.active(atMeasure: endMeasure) {
            let precedingBPM = result.active(atMeasure: startMeasure - 1)?.bpm
            if startMeasure == 1 || precedingBPM != boundary.bpm {
                result.append(TempoChange(id: boundary.id, startMeasure: startMeasure, bpm: boundary.bpm))
            }
        }

        for change in changes where change.startMeasure > endMeasure {
            result.append(
                TempoChange(
                    id: change.id,
                    startMeasure: change.startMeasure - removedMeasures,
                    bpm: change.bpm
                )
            )
        }

        return result.normalizedEnsuringInitialMarker(defaultBPM: defaultBPM)
    }

    private static func rippledTimeSignatureChanges(
        _ changes: [TimeSignatureChange],
        startMeasure: Int,
        endMeasure: Int,
        removedMeasures: Int,
        defaultNumerator: Int,
        defaultDenominator: Int
    ) -> [TimeSignatureChange] {
        var result = changes.filter { $0.startMeasure < startMeasure }

        if let boundary = changes.active(atMeasure: endMeasure) {
            let preceding = result.active(atMeasure: startMeasure - 1)
            let matchesPreceding = preceding?.numerator == boundary.numerator
                && preceding?.denominator == boundary.denominator
            if startMeasure == 1 || !matchesPreceding {
                result.append(
                    TimeSignatureChange(
                        id: boundary.id,
                        numerator: boundary.numerator,
                        denominator: boundary.denominator,
                        startMeasure: startMeasure
                    )
                )
            }
        }

        for change in changes where change.startMeasure > endMeasure {
            result.append(
                TimeSignatureChange(
                    id: change.id,
                    numerator: change.numerator,
                    denominator: change.denominator,
                    startMeasure: change.startMeasure - removedMeasures
                )
            )
        }

        return result.normalizedEnsuringInitialMarker(
            defaultNumerator: defaultNumerator,
            defaultDenominator: defaultDenominator
        )
    }
}
