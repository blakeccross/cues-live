import SwiftData
import SwiftUI

struct EditTransportStatusStrip: View {
    let viewModel: SongEditorViewModel

    var body: some View {
        Group {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, AppSpacing.compact)
        .background(AppColors.surfaceElevated)
    }
}

/// The editor's own playback through the shared toolbar transport, so it matches the setlist window.
struct EditSongTransportCluster: View {
    let viewModel: SongEditorViewModel
    let loopSectionIDs: Set<UUID>
    let currentSectionAtTime: (TimeInterval) -> SongSection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void
    let onToggleFade: () -> Void
    /// Owned by the editor so mapped keys and MIDI drive the same fade the button shows.
    let groupMixFade: GroupMixFadeController
    let onPlay: () -> Void
    /// Time used for the loop button while stopped. Playback leaves this where the insertion is.
    let stoppedDisplayTime: TimeInterval

    @Bindable private var audioEngine = AudioEngineManager.shared

    var body: some View {
        if audioEngine.isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { _ in
                controls(at: audioEngine.currentTime)
            }
        } else {
            controls(at: stoppedDisplayTime)
        }
    }

    private func controls(at time: TimeInterval) -> some View {
        ToolbarTransportControls(
            isPlaying: audioEngine.isPlaying,
            isLoaded: viewModel.isLoaded,
            isLooping: sectionLoopIsActive(at: time),
            canLoop: currentSectionAtTime(time) != nil,
            isFadedOut: groupMixFade.isFadedOut,
            isFading: groupMixFade.isFading,
            onStop: onStopTransport,
            onPlayPause: audioEngine.isPlaying ? viewModel.pause : onPlay,
            onToggleFade: onToggleFade,
            onToggleLoop: { onToggleLoopAtTime(time) }
        )
    }

    private func sectionLoopIsActive(at time: TimeInterval) -> Bool {
        guard let section = currentSectionAtTime(time) else { return false }
        return loopSectionIDs.contains(section.id)
    }
}

#if os(macOS)
struct EditSongToolbarContent: ToolbarContent {
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
    let onAddVideo: () -> Void
    /// Nil hides the back button, as in the separate editor window.
    let onBack: (() -> Void)?
    let currentSectionAtTime: (TimeInterval) -> SongSection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void
    let onToggleFade: () -> Void
    let groupMixFade: GroupMixFadeController
    let onPlay: () -> Void
    let stoppedDisplayTime: TimeInterval
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void
    let onClickTrackGenerated: () -> Void
    @Binding var showingClickEditor: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if let onBack {
            ToolbarItem(placement: .navigation) {
                backButton(action: onBack)
            }
            .cuesHideSharedBackground()
        }

        // The setlist window owns playback while this editor follows it.
        if !viewModel.followsSetlist {
            ToolbarItem(placement: .principal) {
                editorTransportCluster
            }
        }

        ToolbarItem(placement: .principal) {
            LiveToolbarSongTitle(title: song.name, upNext: nil, details: songDetails)
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .principal) {
            generateClickButton
        }

        ToolbarItem(placement: .principal) {
            SmartCuesToolbarToggle(
                song: song,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo
            )
        }

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

    private var songDetails: [LiveToolbarSongTitle.Detail] {
        [
            LiveToolbarSongTitle.Detail(label: "Tempo", value: song.bpm.map { "\(Int($0.rounded()))" } ?? "–"),
            LiveToolbarSongTitle.Detail(label: "Key", value: song.displayedKeyText ?? "–"),
            LiveToolbarSongTitle.Detail(label: "Time", value: song.timeSignatureDisplay ?? "–"),
        ]
    }

    private var editorTransportCluster: some View {
        EditSongTransportCluster(
            viewModel: viewModel,
            loopSectionIDs: loopSectionIDs,
            currentSectionAtTime: currentSectionAtTime,
            onStopTransport: onStopTransport,
            onToggleLoopAtTime: onToggleLoopAtTime,
            onToggleFade: onToggleFade,
            groupMixFade: groupMixFade,
            onPlay: onPlay,
            stoppedDisplayTime: stoppedDisplayTime
        )
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    private var generateClickButton: some View {
        Button {
            showingClickEditor = true
        } label: {
            Label("Generate Click", systemImage: "metronome")
                .labelStyle(.iconOnly)
        }
        .help("Generate Click")
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
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onChangeKey) {
                Label("Change Key", systemImage: "key")
            }
            .disabled(song.sortedTracks.isEmpty)

            Button {
                onImportAbleton()
            } label: {
                Label("Add Ableton File…", systemImage: "doc")
            }

            Button {
                onAddVideo()
            } label: {
                Label(song.videoTrack == nil ? "Add Video…" : "Replace Video…", systemImage: "film")
            }

            Divider()

            if SongSectionDetector.isAvailable {
                Button(isDetectingSections ? "Detecting Sections…" : "Detect Sections") {
                    onDetectSections()
                }
                .disabled(isDetectingSections || SongSectionDetector.analysisTracks(in: song).isEmpty)
                Divider()
            }
            Button("Manage Groups…", action: onManageGroups)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .help("More")
    }
}

/// Turns the song's Smart Cues callouts on and off as one undoable edit.
private struct SmartCuesToolbarToggle: View {
    @Environment(\.modelContext) private var modelContext
    let song: Song
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void

    var body: some View {
        Toggle(isOn: isEnabled) {
            Label("Smart Cues", systemImage: "person.wave.2")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(song.smartGuideEnabled ? "Turn Off Smart Cues" : "Turn On Smart Cues")
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { song.smartGuideEnabled },
            set: { isOn in
                guard isOn != song.smartGuideEnabled else { return }
                let before = captureSnapshot()
                song.smartGuideEnabled = isOn
                try? modelContext.save()
                try? SongProjectBridge.syncProjectFile(for: song, context: modelContext)
                registerUndo("Smart Cues", before, captureSnapshot())
            }
        )
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
