#if os(macOS)
import SwiftData
import SwiftUI

/// Edits one song in the editor window while the setlist keeps playing.
///
/// Holds the per-song editor state that `SongDetailView` holds for the inline editor.
/// Edits are written to the project file shortly after they settle so the setlist screen,
/// which reads the file, shows them; the window is re-created for each new song.
@MainActor
struct SetlistSongEditorHost: View {
    @Environment(\.modelContext) private var modelContext

    let song: Song
    let coordinator: PlaybackCoordinator

    @State private var viewModel: SongEditorViewModel?
    @State private var timeline = SongTimeline()
    @State private var tempoChanges: [TempoChange] = []
    @State private var timeSignatureChanges: [TimeSignatureChange] = []
    @State private var midiEvents: [MIDIEvent] = []
    @State private var undoController = SongUndoController()
    /// The state last written to the project file, so loading it does not count as an edit.
    @State private var persistedState: EditedState?

    /// Setlist waveform and section rebuilds wait this long after the last edit.
    private static let persistDelay: Duration = .milliseconds(300)

    var body: some View {
        Group {
            if let viewModel {
                EditView(
                    song: song,
                    viewModel: viewModel,
                    undoController: undoController,
                    timeline: $timeline,
                    tempoChanges: $tempoChanges,
                    timeSignatureChanges: $timeSignatureChanges,
                    midiEvents: $midiEvents
                )
            } else {
                ProgressView("Loading song…")
                    .tint(AppColors.accent)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusedValue(\.songUndoActions, songUndoActions)
        .onAppear(perform: loadEditor)
        .onDisappear(perform: persistIfEdited)
        .task(id: editedState) {
            guard persistedState != nil, editedState != persistedState else { return }
            try? await Task.sleep(for: Self.persistDelay)
            guard !Task.isCancelled else { return }
            persistIfEdited()
        }
    }

    private var editedState: EditedState {
        EditedState(
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents
        )
    }

    private var songUndoActions: SongUndoActions {
        SongUndoActions(
            canUndo: undoController.canUndo,
            canRedo: undoController.canRedo,
            undoActionName: undoController.undoActionName,
            redoActionName: undoController.redoActionName,
            undo: { undoController.undo() },
            redo: { undoController.redo() }
        )
    }

    private func loadEditor() {
        guard viewModel == nil else { return }
        let model = SongEditorViewModel(song: song, followingSetlist: coordinator)
        model.preloadTrackDurations()
        model.loadSong(context: modelContext)

        _ = try? SongProjectBridge.ensureProjectFile(for: song, context: modelContext)
        if let projectState = try? SongProjectBridge.loadProjectState(for: song) {
            timeline = projectState.timeline
            tempoChanges = projectState.tempoChanges
            timeSignatureChanges = projectState.timeSignatureChanges
            midiEvents = projectState.midiEvents
        }
        persistedState = editedState
        viewModel = model
    }

    private func persistIfEdited() {
        guard let persistedState, editedState != persistedState else { return }
        try? SongProjectBridge.persist(
            song: song,
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents,
            context: modelContext
        )
        self.persistedState = editedState
        coordinator.refreshWaveformAfterEdit(for: song.id)
        coordinator.prepareIncomingSongAfterEdit(song.id)
    }

    private struct EditedState: Hashable {
        var timeline: SongTimeline
        var tempoChanges: [TempoChange]
        var timeSignatureChanges: [TimeSignatureChange]
        var midiEvents: [MIDIEvent]
    }
}
#endif
