import SwiftData
import SwiftUI

struct SmartGuideEditorButton: View {
    enum Chrome {
        case toolbar
        case sheet
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void
    var chrome: Chrome = .toolbar

    @State private var showingEditor = false
    @State private var editStartSnapshot: SongEditSnapshot?

    var body: some View {
        switch chrome {
        case .toolbar:
            toolbarButton
        case .sheet:
            SmartGuideMenu(song: song, viewModel: viewModel)
                .onAppear {
                    editStartSnapshot = captureSnapshot()
                }
                .onDisappear {
                    commitUndoIfNeeded()
                }
        }
    }

    private var toolbarButton: some View {
        Button {
            editStartSnapshot = captureSnapshot()
            showingEditor = true
        } label: {
            Label("Smart Guide", systemImage: "person.wave.2")
                .labelStyle(.iconOnly)
        }
        .tint(song.smartGuideEnabled ? AppColors.accent : nil)
        .help("Smart Guide")
        .popover(isPresented: $showingEditor, arrowEdge: .bottom) {
            SmartGuideMenu(song: song, viewModel: viewModel)
        }
        .onChange(of: showingEditor) { _, isShowing in
            guard !isShowing else { return }
            commitUndoIfNeeded()
        }
    }

    private func commitUndoIfNeeded() {
        guard let before = editStartSnapshot else { return }
        let after = captureSnapshot()
        if before != after {
            registerUndo("Smart Guide", before, after)
        }
        editStartSnapshot = nil
    }
}

struct SmartGuideMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var song: Song
    let viewModel: SongEditorViewModel

    /// A "Cues" track baked by an earlier version would double every callout.
    private var legacyCuesTrack: AudioTrack? {
        song.sortedTracks.first {
            $0.displayName.caseInsensitiveCompare(TrackGroupStore.guideGroupName) == .orderedSame
        }
    }

    private var sectionNames: [String] {
        var seen = Set<String>()
        return SongProjectBridge.projectStateOrDefaults(for: song).markers
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var sectionsWithoutVoice: [String] {
        sectionNames.filter { !SpeechSampleRenderer.hasSample(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Smart Guide")
                .font(.headline)

            Toggle("Call out sections", isOn: $song.smartGuideEnabled)
                .toggleStyle(.switch)

            Text("A voice calls each section one measure before it starts, and calls a looping section on every pass. Cueing a section too late skips the call. Plays through the Cues output.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if song.smartGuideEnabled, let cuesTrack = legacyCuesTrack, !cuesTrack.isMuted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This song has a baked Cues track, so callouts would play twice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Mute Cues Track") {
                        cuesTrack.isMuted = true
                        viewModel.updateMix(for: cuesTrack, context: modelContext)
                    }
                }
            }

            if song.smartGuideEnabled, !sectionsWithoutVoice.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("No voice for:", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(sectionsWithoutVoice.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("These sections will not be called. Rename them to a standard section name to hear them.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
        .onChange(of: song.smartGuideEnabled) { _, _ in
            try? modelContext.save()
            try? SongProjectBridge.syncProjectFile(for: song, context: modelContext)
        }
    }
}

struct ClickTrackEditorButton: View {
    enum Chrome {
        case toolbar
        case sheet
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void
    let onClickTrackGenerated: () -> Void
    var chrome: Chrome = .toolbar

    @State private var showingEditor = false
    @State private var editStartSnapshot: SongEditSnapshot?
    @State private var isGenerating = false
    @State private var generateError: String?

    var body: some View {
        switch chrome {
        case .toolbar:
            toolbarButton
        case .sheet:
            editorMenu
                .onAppear {
                    editStartSnapshot = captureSnapshot()
                }
                .onDisappear {
                    commitUndoIfNeeded()
                }
        }
    }

    private var toolbarButton: some View {
        Button {
            editStartSnapshot = captureSnapshot()
            showingEditor = true
        } label: {
            Label("Click Track", systemImage: "metronome")
                .labelStyle(.iconOnly)
        }
        .tint(ClickTrackFileGenerator.hasClickTrack(in: song) ? AppColors.accent : nil)
        .help("Click Track")
        .popover(isPresented: $showingEditor, arrowEdge: .bottom) {
            editorMenu
        }
        .onChange(of: showingEditor) { _, isShowing in
            guard !isShowing else { return }
            commitUndoIfNeeded()
        }
    }

    private var editorMenu: some View {
        ClickTrackEditorMenu(
            song: song,
            viewModel: viewModel,
            isGenerating: $isGenerating,
            generateError: $generateError,
            onGenerate: generateClick
        )
    }

    private func commitUndoIfNeeded() {
        guard let before = editStartSnapshot else { return }
        let after = captureSnapshot()
        if before != after {
            registerUndo("Generate Click Track", before, after)
        }
        editStartSnapshot = nil
        generateError = nil
    }

    private func closeEditor() {
        showingEditor = false
        if chrome == .sheet {
            dismiss()
        }
    }

    private func generateClick() {
        isGenerating = true
        generateError = nil
        do {
            _ = try ClickTrackFileGenerator.generateAndAttach(to: song, context: modelContext)
            viewModel.reloadSongAfterMediaChange()
            onClickTrackGenerated()
            closeEditor()
        } catch {
            generateError = error.localizedDescription
        }
        isGenerating = false
    }
}

struct ClickTrackEditorMenu: View {
    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    @Binding var isGenerating: Bool
    @Binding var generateError: String?
    let onGenerate: () -> Void

    private var canGenerate: Bool {
        let duration = ClickTrackFileGenerator.timelineDuration(for: song)
        return duration > 0 && !isGenerating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Click Track")
                .font(.headline)

            Button {
                onGenerate()
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(ClickTrackFileGenerator.hasClickTrack(in: song) ? "Regenerate Click" : "Generate Click")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGenerate)

            if let generateError {
                Text(generateError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Creates an audio track with clicks aligned to the song tempo map.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 280)
    }
}
