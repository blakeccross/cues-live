import Foundation

/// Places clicks on the tempo map: an accent on each downbeat, then one click every `rhythm`.
enum ClickScheduler {
    struct ScheduledClick: Equatable {
        let time: TimeInterval
        let isAccent: Bool
    }

    static func scheduledClicks(
        from startTime: TimeInterval,
        to endTime: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        rhythm: ClickRhythm
    ) -> [ScheduledClick] {
        guard endTime > startTime else { return [] }

        let normalizedTempo = tempoChanges.normalizedEnsuringInitialMarker(
            defaultBPM: tempoChanges.referenceBPM
        )
        let normalizedSignatures = timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: MeasureTiming.defaultNumerator,
            defaultDenominator: MeasureTiming.defaultDenominator
        )

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
            guard timeline.bpm(atTick: barTick) > 0 else { break }

            let signature = MeasureTiming.numeratorDenominatorForMeasure(
                measure,
                changes: normalizedSignatures
            )
            let quarters = MeasureTiming.beatsPerMeasure(
                numerator: signature.numerator,
                denominator: signature.denominator
            )
            let measureTicks = max(0, Int((quarters * Double(TempoChange.ticksPerQuarter)).rounded()))
            let tickStep = max(1, rhythm.ticksPerClick(denominator: signature.denominator))

            for offset in stride(from: 0, to: max(measureTicks, 1), by: tickStep) {
                let clickTime = timeline.seconds(atTick: barTick + offset)
                if clickTime >= endTime { break }
                if clickTime >= startTime {
                    result.append(ScheduledClick(time: clickTime, isAccent: offset == 0))
                }
            }

            barTick += measureTicks
            measure += 1
        }

        return result
    }
}
