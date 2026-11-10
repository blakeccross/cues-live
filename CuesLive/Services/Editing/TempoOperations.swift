import Foundation

/// How a tempo ramp approaches its end BPM. The map stays stepwise, and the curve is sampled onto it.
enum TempoCurve: String, CaseIterable, Identifiable {
    case linear
    case parabolic
    case sCurve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: "Linear"
        case .parabolic: "Parabolic"
        case .sCurve: "S-Curve"
        }
    }
}

/// Spacing of the tempo events a curve writes. The default is an eighth note.
enum TempoResolution: String, CaseIterable, Identifiable {
    case whole = "1/1"
    case half = "1/2"
    case quarter = "1/4"
    case eighth = "1/8"
    case sixteenth = "1/16"

    var id: String { rawValue }

    var ticks: Int {
        switch self {
        case .whole: TempoChange.ticksPerQuarter * 4
        case .half: TempoChange.ticksPerQuarter * 2
        case .quarter: TempoChange.ticksPerQuarter
        case .eighth: TempoChange.ticksPerQuarter / 2
        case .sixteenth: TempoChange.ticksPerQuarter / 4
        }
    }
}

enum TempoOperationError: Equatable, Error {
    case rangeTooShort
    case tooManyEvents
    case invalidBPM(Double)
    case invalidFactor

    var message: String {
        switch self {
        case .rangeTooShort:
            "The range is too short."
        case .tooManyEvents:
            "That range needs too many tempo events. Use a coarser resolution."
        case .invalidBPM(let bpm):
            String(format: "%.1f BPM is outside %.0f–%.0f.", bpm, TempoChange.validBPMRange.lowerBound, TempoChange.validBPMRange.upperBound)
        case .invalidFactor:
            "The factor must be between 0.05 and 20."
        }
    }
}

/// Tempo operations on a bar range.
///
/// Constant, linear, parabolic, and S-curve edits replace the tempo inside
/// `[start, end)` and write the tempo that was in effect at `end` back onto
/// `end`, unless an event was already there. The end is a musical position, so
/// it is read before the edit. Stretch scales the tempos inside the range so
/// the same bars last `factor` times as long, and keeps the tempo at the end.
/// Scale multiplies every tempo in the song.
enum TempoOperations {
    static let maxEvents = 10_000

    static func constant(
        bpm: Double,
        from startTick: Int,
        to endTick: Int,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Result<[TempoChange], TempoOperationError> {
        guard TempoChange.validBPMRange.contains(bpm) else { return .failure(.invalidBPM(bpm)) }
        var edit = TempoEdit(changes: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let start = max(0, startTick)
        let end = max(0, endTick)
        if end <= start {
            if let error = edit.set(tick: start, bpm: bpm) { return .failure(error) }
            return .success(edit.finalized())
        }

        let after = edit.bpm(at: end)
        let hadEnd = edit.hasEvent(at: end)
        if let error = edit.set(tick: start, bpm: bpm) { return .failure(error) }
        edit.removeInterior(from: start, to: end)
        if !hadEnd, let error = edit.set(tick: end, bpm: after) { return .failure(error) }
        return .success(edit.finalized())
    }

    static func curve(
        _ curve: TempoCurve,
        startBPM: Double?,
        endBPM: Double,
        from startTick: Int,
        to endTick: Int,
        resolutionTicks: Int,
        curvature: Double = 0.5,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Result<[TempoChange], TempoOperationError> {
        let start = max(0, startTick)
        let end = max(0, endTick)
        guard end > start else { return .failure(.rangeTooShort) }
        let resolution = max(1, resolutionTicks)
        if (end - start) / resolution > maxEvents { return .failure(.tooManyEvents) }
        guard TempoChange.validBPMRange.contains(endBPM) else { return .failure(.invalidBPM(endBPM)) }

        var edit = TempoEdit(changes: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let startTempo = startBPM ?? edit.bpm(at: start)
        guard TempoChange.validBPMRange.contains(startTempo) else { return .failure(.invalidBPM(startTempo)) }
        let bend = min(1, max(-1, curvature))
        let after = edit.bpm(at: end)
        let hadEnd = edit.hasEvent(at: end)
        edit.removeInterior(from: start, to: end)

        var tick = start
        while tick < end {
            let fraction = Double(tick - start) / Double(end - start)
            let bpm = startTempo + (endBPM - startTempo) * gain(curve, fraction: fraction, curvature: bend)
            if let error = edit.set(tick: tick, bpm: bpm) { return .failure(error) }
            tick += resolution
        }
        if !hadEnd, let error = edit.set(tick: end, bpm: after) { return .failure(error) }
        return .success(edit.finalized())
    }

    /// Divides tempos inside the range by `factor`, so the bars last `factor` times as long.
    static func stretch(
        factor: Double,
        from startTick: Int,
        to endTick: Int,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Result<[TempoChange], TempoOperationError> {
        guard factor.isFinite, (0.05...20).contains(factor) else { return .failure(.invalidFactor) }
        let start = max(0, startTick)
        let end = max(0, endTick)
        guard end > start else { return .failure(.rangeTooShort) }

        var edit = TempoEdit(changes: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let after = edit.bpm(at: end)
        let hadEnd = edit.hasEvent(at: end)
        var events = edit.events(from: start, to: end)
        events.append((start, edit.bpm(at: start)))
        for (tick, bpm) in events {
            if let error = edit.set(tick: tick, bpm: bpm / factor) { return .failure(error) }
        }
        if !hadEnd, let error = edit.set(tick: end, bpm: after) { return .failure(error) }
        return .success(edit.finalized())
    }

    static func scale(
        factor: Double,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Result<[TempoChange], TempoOperationError> {
        guard factor.isFinite, factor > 0 else { return .failure(.invalidFactor) }
        var edit = TempoEdit(changes: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        for change in tempoChanges {
            let tick = edit.tick(of: change)
            if let error = edit.set(tick: tick, bpm: change.bpm * factor) { return .failure(error) }
        }
        return .success(edit.finalized())
    }

    private static func gain(_ curve: TempoCurve, fraction: Double, curvature: Double) -> Double {
        switch curve {
        case .linear:
            fraction
        case .parabolic:
            pow(fraction, pow(2.0, curvature * 2.0))
        case .sCurve:
            0.5 - 0.5 * cos(fraction * Double.pi)
        }
    }
}

/// Mutable tempo map used while one operation is applied. Positions are ticks.
private struct TempoEdit {
    private var changes: [TempoChange]
    private let signatures: [TimeSignatureChange]

    init(changes: [TempoChange], timeSignatureChanges: [TimeSignatureChange]) {
        self.changes = changes
        signatures = timeSignatureChanges
    }

    func tick(of change: TempoChange) -> Int {
        TempoTimeline.tick(
            measure: change.startMeasure,
            beatOffset: change.beatOffset,
            timeSignatureChanges: signatures
        )
    }

    func bpm(at tick: Int) -> Double {
        TempoTimeline(tempoChanges: changes, timeSignatureChanges: signatures).bpm(atTick: tick)
    }

    func hasEvent(at tick: Int) -> Bool {
        changes.contains { self.tick(of: $0) == tick }
    }

    /// Events strictly inside the range, with the BPM they hold now.
    func events(from start: Int, to end: Int) -> [(Int, Double)] {
        changes.compactMap { change in
            let tick = tick(of: change)
            guard tick > start, tick < end else { return nil }
            return (tick, change.bpm)
        }
    }

    mutating func removeInterior(from start: Int, to end: Int) {
        let signatures = signatures
        changes = changes.filter { change in
            let tick = TempoTimeline.tick(
                measure: change.startMeasure,
                beatOffset: change.beatOffset,
                timeSignatureChanges: signatures
            )
            return tick <= start || tick >= end
        }
    }

    mutating func set(tick position: Int, bpm: Double) -> TempoOperationError? {
        guard TempoChange.validBPMRange.contains(bpm) else { return .invalidBPM(bpm) }
        let location = TempoTimeline.location(tick: position, timeSignatureChanges: signatures)
        let signatures = signatures
        if let index = changes.firstIndex(where: { change in
            TempoTimeline.tick(
                measure: change.startMeasure,
                beatOffset: change.beatOffset,
                timeSignatureChanges: signatures
            ) == position
        }) {
            let existing = changes[index]
            changes[index] = TempoChange(
                id: existing.id,
                startMeasure: location.measure,
                beatOffset: location.beatOffset,
                bpm: bpm,
                sortOrder: existing.sortOrder
            )
        } else {
            changes.append(
                TempoChange(
                    startMeasure: location.measure,
                    beatOffset: location.beatOffset,
                    bpm: bpm
                )
            )
        }
        return nil
    }

    func finalized() -> [TempoChange] {
        let origin = changes.first { $0.isOrigin }?.bpm ?? changes.referenceBPM
        return changes.normalizedEnsuringInitialMarker(defaultBPM: origin)
    }
}
