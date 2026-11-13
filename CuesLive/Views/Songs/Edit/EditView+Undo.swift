import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditView {
    func persistProjectState() {
        try? SongProjectBridge.persist(
            song: song,
            timeline: timeline,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            midiEvents: midiEvents,
            context: modelContext
        )
    }

    func captureSnapshot() -> SongEditSnapshot {
        SongEditSnapshot.capture(
            song: song,
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents
        )
    }

    func applySnapshot(_ snapshot: SongEditSnapshot) {
        timeline = snapshot.timeline
        clipSelection.retain(existing: timeline.clips)
        midiEvents = snapshot.midiEvents

        snapshot.applyMetadata(to: song)
        let trackIDsBeforeApply = Set(song.sortedTracks.map(\.id))
        snapshot.applyTracks(to: song, context: modelContext)
        snapshot.applyMIDILaneHeights(to: song)
        let trackIDsChanged = trackIDsBeforeApply != Set(song.sortedTracks.map(\.id))

        let defaultBPM = song.bpm ?? TempoChange.defaultBPM
        let defaultNumerator = song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator
        let defaultDenominator = song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
        let normalizedTempo = snapshot.normalizedTempoChanges(defaultBPM: defaultBPM)
        let normalizedTimeSignature = snapshot.normalizedTimeSignatureChanges(
            defaultNumerator: defaultNumerator,
            defaultDenominator: defaultDenominator
        )
        tempoChanges = normalizedTempo
        timeSignatureChanges = normalizedTimeSignature

        try? SongProjectBridge.persist(
            song: song,
            timeline: timeline,
            tempoChanges: normalizedTempo,
            timeSignatureChanges: normalizedTimeSignature,
            midiEvents: midiEvents,
            context: modelContext
        )
        try? modelContext.save()

        syncPlayback()
        viewModel.syncTempoMap(normalizedTempo, timeSignatureChanges: normalizedTimeSignature)

        // Mix settings carry each stem's live key shift, so undoing a key change needs no reload.
        for track in song.sortedTracks {
            viewModel.updateMix(for: track, context: modelContext)
        }

        reconfigureMIDI()

        if trackIDsChanged {
            viewModel.loadSong(context: modelContext)
        }
    }

    func performUndoableChange(_ actionName: String, _ change: () -> Void) {
        guard !undoController.isApplyingUndo else {
            change()
            return
        }
        let before = captureSnapshot()
        change()
        registerSnapshotChange(actionName, before: before, after: captureSnapshot())
    }

    /// Records an edit made elsewhere as one undo step that restores the given snapshots.
    func registerSnapshotChange(_ actionName: String, before: SongEditSnapshot, after: SongEditSnapshot) {
        undoController.registerChange(
            actionName: actionName,
            before: before,
            after: after,
            apply: { snapshot in
                applySnapshot(snapshot)
            }
        )
    }

    /// Picks up timeline changes written straight to the project file, such as a regenerated click clip.
    func reloadTimelineFromProject() {
        guard let state = try? SongProjectBridge.loadProjectState(for: song) else { return }
        timeline = state.timeline
        syncPlayback()
    }

    func syncPlayback() {
        viewModel.syncArrangement(timeline)
    }

    /// Applies one timeline edit as a single undo step, then saves and updates playback.
    func commitTimelineEdit(_ actionName: String, _ edit: (inout SongTimeline) -> Void) {
        performUndoableChange(actionName) {
            edit(&timeline)
            persistProjectState()
            syncPlayback()
            prepareSectionAnnouncements()
        }
    }
}
