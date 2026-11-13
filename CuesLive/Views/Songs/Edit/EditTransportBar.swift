import SwiftData
import SwiftUI

struct EditTransportBar<Chrome: View>: View {
    let viewModel: SongEditorViewModel
    @Bindable var song: Song
    @Binding var showingArrangementEditor: Bool
    let arrangementActions: ArrangementSectionActions
    let loopSectionIDs: Set<UUID>
    let isDetectingSections: Bool
    let onChangeKey: () -> Void
    let onManageGroups: () -> Void
    let onDetectSections: () -> Void
    let onImportAbleton: () -> Void
    let onAddMIDILane: () -> Void
    let onClearMarkerCue: () -> Void
    let captureSnapshot: () -> SongEditSnapshot
    let currentSectionAtTime: (TimeInterval) -> SongSection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void
    let onToggleFade: () -> Void
    /// Owned by the editor so mapped keys and MIDI drive the same fade the button shows.
    let groupMixFade: GroupMixFadeController
    let onPlay: () -> Void
    /// Time used for the loop button while stopped. Playback leaves this where the insertion is.
    let stoppedDisplayTime: TimeInterval
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void
    let onClickTrackGenerated: () -> Void
    let onBack: () -> Void
    let undoController: SongUndoController
    let content: Chrome

    @State private var showingClickEditor = false
    @State private var showingSmartGuideEditor = false
    @Bindable private var audioEngine = AudioEngineManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(AppColors.surfaceElevated)
            }
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LiveTransportBottomBar {
                transportCluster
            }
        }
        #if os(iOS)
        .toolbar {
            editorToolbar
        }
        #endif
        .sheet(isPresented: $showingClickEditor) {
            ClickTrackEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo,
                onClickTrackGenerated: onClickTrackGenerated,
                chrome: .sheet
            )
        }
        .sheet(isPresented: $showingSmartGuideEditor) {
            SmartGuideEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo,
                chrome: .sheet
            )
        }
        .sheet(isPresented: $showingArrangementEditor) {
            ArrangementEditorMenu(actions: arrangementActions)
            .padding(AppSpacing.md)
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            backButton
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                undoController.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!undoController.canUndo)
            .accessibilityLabel(undoController.undoActionName.map { "Undo \($0)" } ?? "Undo")

            Button {
                undoController.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!undoController.canRedo)
            .accessibilityLabel(undoController.redoActionName.map { "Redo \($0)" } ?? "Redo")

            Button(action: onAddMIDILane) {
                Label("Add MIDI Lane", systemImage: "pianokeys")
                    .labelStyle(.iconOnly)
            }
            .help("Add MIDI Lane")

            overflowMenu
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button(action: onChangeKey) {
                Label("Change Key", systemImage: "key")
            }
            .disabled(song.sortedTracks.isEmpty)

            Button {
                showingClickEditor = true
            } label: {
                Label("Generate Click", systemImage: "metronome")
            }

            Button {
                showingSmartGuideEditor = true
            } label: {
                Label("Smart Cues", systemImage: "person.wave.2")
            }

            Button {
                onImportAbleton()
            } label: {
                Label("Add Ableton File…", systemImage: "doc")
            }

            if !arrangementActions.sections.isEmpty {
                Button {
                    showingArrangementEditor = true
                } label: {
                    Label("Arrangement", systemImage: "list.bullet.rectangle")
                }
            }

            Divider()

            if SongSectionDetector.isAvailable {
                Button {
                    onDetectSections()
                } label: {
                    Label(isDetectingSections ? "Detecting Sections…" : "Detect Sections", systemImage: "wand.and.stars")
                }
                .disabled(isDetectingSections || SongSectionDetector.analysisTracks(in: song).isEmpty)
            }

            Button("Manage Groups…", action: onManageGroups)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Back", systemImage: "chevron.backward")
                .labelStyle(.iconOnly)
        }
        .help("Back")
    }
    #endif

    private var transportCluster: some View {
        Group {
            if audioEngine.isPlaying {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { _ in
                    transportStrip(at: audioEngine.currentTime)
                }
            } else {
                transportStrip(at: stoppedDisplayTime)
            }
        }
    }

    private func transportStrip(at time: TimeInterval) -> some View {
        SharedTransportStrip(
            buttonSize: 44,
            isPlaying: audioEngine.isPlaying,
            isLoaded: viewModel.isLoaded,
            isLooping: sectionLoopIsActive(at: time),
            canLoop: currentSectionAtTime(time) != nil,
            onStop: onStopTransport,
            onPlay: onPlay,
            onPause: viewModel.pause,
            onToggleLoop: { onToggleLoopAtTime(time) },
            isFadedOut: groupMixFade.isFadedOut,
            isFading: groupMixFade.isFading,
            onToggleFade: onToggleFade
        )
    }

    private func sectionLoopIsActive(at time: TimeInterval) -> Bool {
        guard let section = currentSectionAtTime(time) else { return false }
        return loopSectionIDs.contains(section.id)
    }

}
