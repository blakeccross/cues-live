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
        let timeline = TempoTimeline(
            tempoChanges: normalizedTempo,
            timeSignatureChanges: normalizedSignatures
        )
        var result: [ScheduledClick] = []
        var measure = max(
            1,
            MeasureTiming.measureIndex(
                at: startTime,
                tempoChanges: normalizedTempo,
                timeSignatureChanges: normalizedSignatures
            )
        )
        var barTick = TempoTimeline.tick(
            measure: measure,
            beatOffset: 0,
            timeSignatureChanges: normalizedSignatures
        )

        while measure <= 1_000_000 {
            let measureStart = timeline.seconds(atTick: barTick)
            if measureStart >= endTime { break }

            let bpm = timeline.bpm(atTick: barTick)
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
            let tickStep = TempoChange.ticksPerQuarter / subdivisionsPerBeat
            let subdivisionsInMeasure = max(1, beatsInMeasure) * subdivisionsPerBeat

            for subdivisionIndex in 0..<subdivisionsInMeasure {
                let clickTime = timeline.seconds(atTick: barTick + subdivisionIndex * tickStep)
                if clickTime >= endTime { break }
                if clickTime >= startTime {
                    result.append(
                        ScheduledClick(time: clickTime, isAccent: subdivisionIndex == 0)
                    )
                }
            }

            let quarters = MeasureTiming.beatsPerMeasure(
                numerator: signature.numerator,
                denominator: signature.denominator
            )
            barTick += max(0, Int((quarters * Double(TempoChange.ticksPerQuarter)).rounded()))
            measure += 1
        }

        return result
    }
}
