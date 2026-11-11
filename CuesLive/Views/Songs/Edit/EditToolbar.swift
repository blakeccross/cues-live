import SwiftData
import SwiftUI

struct EditTransportStatusStrip: View {
    let viewModel: SongEditorViewModel

    var body: some View {
        Group {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(AppColors.surfaceElevated)
    }
}

#if os(macOS)
struct EditSongTransportCluster: View {
    let viewModel: SongEditorViewModel
    let loopSectionIDs: Set<UUID>
    let currentSectionAtTime: (TimeInterval) -> SongSection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void
    let onPlay: () -> Void
    /// Time used for the loop button while stopped. Playback leaves this where the insertion is.
    let stoppedDisplayTime: TimeInterval

    @State private var groupMixFade = GroupMixFadeController()
    @Bindable private var audioEngine = AudioEngineManager.shared
    @Environment(\.modelContext) private var modelContext

    var body: some View {
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
            onStop: {
                groupMixFade.clearFade(context: modelContext) {
                    audioEngine.applyGroupMix(GroupMixStore.snapshot(in: modelContext))
                    try? modelContext.save()
                }
                onStopTransport()
            },
            onPlay: onPlay,
            onPause: viewModel.pause,
            onToggleLoop: { onToggleLoopAtTime(time) },
            isFadedOut: groupMixFade.isFadedOut,
            isFading: groupMixFade.isFading,
            onToggleFade: {
                groupMixFade.toggleFade(context: modelContext) {
                    audioEngine.applyGroupMix(GroupMixStore.snapshot(in: modelContext))
                } onComplete: {
                    try? modelContext.save()
                }
            }
        )
    }

    private func sectionLoopIsActive(at time: TimeInterval) -> Bool {
        guard let section = currentSectionAtTime(time) else { return false }
        return loopSectionIDs.contains(section.id)
    }
}

struct EditSongToolbarContent: ToolbarContent {
    let viewModel: SongEditorViewModel
    @Bindable var song: Song
    @Binding var showingArrangementEditor: Bool
    @Binding var showingChangeKey: Bool
    let arrangementActions: ArrangementSectionActions
    let loopSectionIDs: Set<UUID>
    @Binding var showingSongLibrary: Bool
    @Binding var showingGroupEditor: Bool
    let isDetectingSections: Bool
    let onDetectSections: () -> Void
    let onImportAbleton: () -> Void
    let onAddMIDILane: () -> Void
    let onBack: () -> Void
    let currentSectionAtTime: (TimeInterval) -> SongSection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void
    let onPlay: () -> Void
    let stoppedDisplayTime: TimeInterval
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void
    let onClickTrackGenerated: () -> Void
    @Binding var showingClickEditor: Bool
    @Binding var showingSmartGuideEditor: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            backButton
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .principal) {
            if LiveTransportLayout.macOSPlacesControlsAtBottom {
                LiveToolbarSongTitle(title: song.name, upNext: nil)
            } else {
                editorTransportCluster
            }
        }
        .cuesHideSharedBackground()

        if !arrangementActions.sections.isEmpty {
            ToolbarItem(placement: .automatic) {
                arrangementEditorButton
            }
            .cuesHideSharedBackground()
        }

        ToolbarItem(placement: .automatic) {
            midiLaneButton
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            moreMenu
        }
        .cuesHideSharedBackground()
    }

    private var editorTransportCluster: some View {
        EditSongTransportCluster(
            viewModel: viewModel,
            loopSectionIDs: loopSectionIDs,
            currentSectionAtTime: currentSectionAtTime,
            onStopTransport: onStopTransport,
            onToggleLoopAtTime: onToggleLoopAtTime,
            onPlay: onPlay,
            stoppedDisplayTime: stoppedDisplayTime
        )
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Back", systemImage: "chevron.backward")
                .labelStyle(.iconOnly)
        }
        .help("Back")
    }

    private var arrangementEditorButton: some View {
        Button {
            showingArrangementEditor = true
        } label: {
            Label("Arrangement", systemImage: "list.bullet.rectangle")
                .labelStyle(.iconOnly)
        }
        .help("Arrangement")
        .popover(isPresented: $showingArrangementEditor, arrowEdge: .bottom) {
            ArrangementEditorMenu(actions: arrangementActions)
        }
    }

    private var midiLaneButton: some View {
        Button(action: onAddMIDILane) {
            Label("Add MIDI Lane", systemImage: "pianokeys")
                .labelStyle(.iconOnly)
        }
        .help("Add MIDI Lane")
    }

    private var moreMenu: some View {
        Menu {
            Button {
                showingChangeKey = true
            } label: {
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

            Divider()

            if SongSectionDetector.isAvailable {
                Button(isDetectingSections ? "Detecting Sections…" : "Detect Sections") {
                    onDetectSections()
                }
                .disabled(isDetectingSections || SongSectionDetector.analysisTracks(in: song).isEmpty)
                Divider()
            }
            Button("Manage Groups…") {
                showingGroupEditor = true
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .help("More")
        .popover(isPresented: $showingClickEditor, arrowEdge: .bottom) {
            ClickTrackEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo,
                onClickTrackGenerated: onClickTrackGenerated,
                chrome: .sheet
            )
        }
        .popover(isPresented: $showingSmartGuideEditor, arrowEdge: .bottom) {
            SmartGuideEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo,
                chrome: .sheet
            )
        }
    }
}
#endif

struct DetectSectionsFlowModifier: ViewModifier {
    @Binding var showingReplaceConfirm: Bool
    @Binding var error: String?
    let onConfirmReplace: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Replace existing sections?",
                isPresented: $showingReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("Replace Sections", role: .destructive, action: onConfirmReplace)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Detected sections replace the current ones and reset arrangement edits such as reordered, trimmed or looped sections. You can undo this.")
            }
            .alert("Couldn’t Detect Sections", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }
}
