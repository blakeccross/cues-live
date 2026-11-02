import Foundation

enum ClickTrackScheduler {
    struct ScheduledClick: Equatable {
        let time: TimeInterval
        let isAccent: Bool
    }

    static func scheduledClicks(
        from startTime: TimeInterval,
        to endTime: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        subdivision: ClickTrackSubdivision
    ) -> [ScheduledClick] {
        guard endTime > startTime else { return [] }

        let normalizedTempo = tempoChanges.normalizedEnsuringInitialMarker(
            defaultBPM: tempoChanges.referenceBPM
        )
        let normalizedSignatures = timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: MeasureTiming.defaultNumerator,
            defaultDenominator: MeasureTiming.defaultDenominator
        )

        let subdivisionsPerBeat = subdivision.subdivisionsPerBeat
        var result: [ScheduledClick] = []
        var measure = max(
            1,
            MeasureTiming.measureIndex(
                at: startTime,
                tempoChanges: normalizedTempo,
                timeSignatureChanges: normalizedSignatures
            )
        )

        while measure <= 1_000_000 {
            let measureStart = MeasureTiming.timeAtStartOfMeasure(
                measure,
                tempoChanges: normalizedTempo,
                timeSignatureChanges: normalizedSignatures
            )
            if measureStart >= endTime { break }

            let bpm = MeasureTiming.bpmForMeasure(measure, tempoChanges: normalizedTempo)
            guard bpm > 0 else { break }

            let signature = MeasureTiming.numeratorDenominatorForMeasure(
                measure,
                changes: normalizedSignatures
            )
            let beatsInMeasure = Int(
                MeasureTiming.beatsPerMeasure(
                    numerator: signature.numerator,
                    denominator: signature.denominator
                ).rounded(.down)
            )
            let beatDuration = 60.0 / bpm
            let subdivisionDuration = beatDuration / Double(subdivisionsPerBeat)
            let subdivisionsInMeasure = max(1, beatsInMeasure) * subdivisionsPerBeat

            for subdivisionIndex in 0..<subdivisionsInMeasure {
                let clickTime = measureStart + TimeInterval(subdivisionIndex) * subdivisionDuration
                if clickTime >= endTime { break }
                if clickTime >= startTime {
                    result.append(
                        ScheduledClick(time: clickTime, isAccent: subdivisionIndex == 0)
                    )
                }
            }

            measure += 1
        }

        return result
    }
}
