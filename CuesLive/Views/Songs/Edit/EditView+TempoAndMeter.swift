import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditView {
    private var measureNumerator: Int {
        normalizedTimeSignatureChanges.referenceNumerator
    }

    private var measureDenominator: Int {
        normalizedTimeSignatureChanges.referenceDenominator
    }

    var normalizedTimeSignatureChanges: [TimeSignatureChange] {
        timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator,
            defaultDenominator: song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
        )
    }

    var normalizedTempoChanges: [TempoChange] {
        tempoChanges.normalizedEnsuringInitialMarker(defaultBPM: song.bpm ?? TempoChange.defaultBPM)
    }

    private func persistTempoChanges() {
        let normalized = normalizedTempoChanges
        tempoChanges = normalized
        if song.bpm != normalized.referenceBPM {
            song.bpm = normalized.referenceBPM
            try? modelContext.save()
        }
        persistProjectState()
        viewModel.syncTempoMap(normalized, timeSignatureChanges: normalizedTimeSignatureChanges)
    }

    private func persistTimeSignatureChanges() {
        let normalized = normalizedTimeSignatureChanges
        timeSignatureChanges = normalized
        if song.timeSignatureNumerator != normalized.referenceNumerator {
            song.timeSignatureNumerator = normalized.referenceNumerator
            try? modelContext.save()
        }
        if song.timeSignatureDenominator != normalized.referenceDenominator {
            song.timeSignatureDenominator = normalized.referenceDenominator
            try? modelContext.save()
        }
        persistProjectState()
        viewModel.syncTempoMap(normalizedTempoChanges, timeSignatureChanges: normalized)
    }

    func handleTempoRulerTap(at time: TimeInterval) {
        let boundary = MeasureTiming.nearestMeasureBoundary(
            to: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let existing = normalizedTempoChanges.first {
            $0.startMeasure == boundary.measure && $0.isDownbeat
        }
        let bpm = existing?.bpm ?? MeasureTiming.activeBPM(
            at: boundary.time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        activeSheet = .tempoChange(TempoLanePrompt(
            measure: boundary.measure,
            bpm: bpm,
            markerID: existing?.id
        ))
    }

    func deleteTempoMarker(_ marker: TempoChange) {
        guard !marker.isOrigin else { return }
        performUndoableChange("Delete Tempo Marker") {
            tempoChanges.removeAll { $0.id == marker.id }
            tempoChanges = normalizedTempoChanges
            persistTempoChanges()
        }
    }

    func handleTimeSignatureRulerTap(at time: TimeInterval) {
        let boundary = MeasureTiming.nearestMeasureBoundary(
            to: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let existing = normalizedTimeSignatureChanges.first { $0.startMeasure == boundary.measure }
        let active = existing
            ?? normalizedTimeSignatureChanges.active(atMeasure: boundary.measure)
            ?? normalizedTimeSignatureChanges.first
        activeSheet = .timeSignatureChange(TimeSignatureLanePrompt(
            measure: boundary.measure,
            numerator: active?.numerator ?? measureNumerator,
            denominator: active?.denominator ?? measureDenominator,
            markerID: existing?.id
        ))
    }

    func moveTimeSignatureMarker(_ marker: TimeSignatureChange, to time: TimeInterval) {
        guard marker.startMeasure > 1 else { return }
        let boundary = MeasureTiming.nearestMeasureBoundary(
            to: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        guard boundary.measure > 1, boundary.measure != marker.startMeasure else { return }
        guard !normalizedTimeSignatureChanges.contains(where: {
            $0.id != marker.id && $0.startMeasure == boundary.measure
        }) else { return }

        performUndoableChange("Move Time Signature") {
            timeSignatureChanges = timeSignatureChanges.map { change in
                guard change.id == marker.id else { return change }
                return TimeSignatureChange(
                    id: change.id,
                    numerator: change.numerator,
                    denominator: change.denominator,
                    startMeasure: boundary.measure,
                    sortOrder: change.sortOrder
                )
            }
            persistTimeSignatureChanges()
        }
    }

    func moveTempoMarker(_ marker: TempoChange, to time: TimeInterval) {
        guard !marker.isOrigin else { return }
        let snapped = MeasureTiming.snapToNearestBeat(
            time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let timeline = TempoTimeline(
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let tick = Int(timeline.tick(atSeconds: max(0, snapped)).rounded())
        let location = TempoTimeline.location(
            tick: tick,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        guard location.measure > 1 || location.beatOffset > 0.000_001 else { return }
        let moved = TempoChange(
            id: marker.id,
            startMeasure: location.measure,
            beatOffset: location.beatOffset,
            bpm: marker.bpm,
            sortOrder: marker.sortOrder
        )
        guard !marker.occupiesSamePosition(as: moved) else { return }
        guard !normalizedTempoChanges.contains(where: {
            $0.id != marker.id && $0.occupiesSamePosition(as: moved)
        }) else { return }

        performUndoableChange("Move Tempo") {
            tempoChanges = tempoChanges.map { change in
                change.id == marker.id ? moved : change
            }
            persistTempoChanges()
        }
    }

    func deleteTimeSignatureMarker(_ marker: TimeSignatureChange) {
        guard marker.startMeasure > 1 else { return }
        performUndoableChange("Delete Time Signature Marker") {
            timeSignatureChanges.removeAll { $0.id == marker.id }
            timeSignatureChanges = normalizedTimeSignatureChanges
            persistTimeSignatureChanges()
        }
    }

    func applyTempoOperation(_ changes: [TempoChange]) {
        performUndoableChange("Tempo Operation") {
            tempoChanges = changes
            persistTempoChanges()
            showingTempoOperations = false
        }
    }

    /// Sets the tempo at the prompt's bar. Locked tracks are re-timed to stay on the beat and
    /// stretched live; every other track keeps playing as it did.
    func applyTempoChange(prompt: TempoLanePrompt, bpm: Double, lockedTrackIDs: Set<UUID>) {
        guard TempoChange.validBPMRange.contains(bpm) else { return }

        performUndoableChange("Edit Tempo") {
            let tempoBefore = currentTempoTimeline
            if let markerID = prompt.markerID,
               tempoChanges.contains(where: { $0.id == markerID }) {
                tempoChanges = tempoChanges.map { change in
                    guard change.id == markerID else { return change }
                    return TempoChange(
                        id: change.id,
                        startMeasure: change.startMeasure,
                        beatOffset: change.beatOffset,
                        bpm: bpm,
                        sortOrder: change.sortOrder
                    )
                }
            } else {
                tempoChanges.append(TempoChange(startMeasure: prompt.measure, bpm: bpm))
            }
            retimeLockedTracks(lockedTrackIDs, from: tempoBefore)
            persistTempoChanges()
            activeSheet = nil
        }
    }

    private var currentTempoTimeline: TempoTimeline {
        TempoTimeline(
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
    }

    /// Moves the locked tracks' audio, the sections and the MIDI cues from `tempoBefore` to the
    /// current tempo map. Call before persisting, so one save writes the tempo and the clips.
    private func retimeLockedTracks(_ lockedTrackIDs: Set<UUID>, from tempoBefore: TempoTimeline) {
        let retimed = TempoTrackLock.retime(
            timeline,
            midiEvents: midiEvents,
            lockedTrackIDs: lockedTrackIDs,
            from: tempoBefore,
            to: currentTempoTimeline
        )
        guard retimed.timeline != timeline || retimed.midiEvents != midiEvents else { return }
        timeline = retimed.timeline
        midiEvents = retimed.midiEvents
        clipSelection.retain(existing: timeline.clips)
        syncPlayback()
        reconfigureMIDI()
        prepareSectionAnnouncements()
    }

    func applyTimeSignatureChange(
        prompt: TimeSignatureLanePrompt,
        numerator: Int,
        denominator: Int
    ) {
        guard (1...32).contains(numerator),
              TimeSignatureChange.validDenominators.contains(denominator) else { return }

        performUndoableChange("Edit Time Signature") {
            if let markerID = prompt.markerID,
               timeSignatureChanges.contains(where: { $0.id == markerID }) {
                timeSignatureChanges = timeSignatureChanges.map { change in
                    guard change.id == markerID else { return change }
                    return TimeSignatureChange(
                        id: change.id,
                        numerator: numerator,
                        denominator: denominator,
                        startMeasure: change.startMeasure,
                        sortOrder: change.sortOrder
                    )
                }
            } else {
                timeSignatureChanges.append(
                    TimeSignatureChange(
                        numerator: numerator,
                        denominator: denominator,
                        startMeasure: prompt.measure
                    )
                )
            }
            persistTimeSignatureChanges()
            activeSheet = nil
        }
    }
}
