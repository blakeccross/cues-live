import SwiftData
import SwiftUI

struct CueTrackEditorButton: View {
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
            Label("Cue Track", systemImage: "person.wave.2")
                .labelStyle(.iconOnly)
        }
        .tint(CueTrackFileGenerator.hasCueTrack(in: song) ? AppColors.accent : nil)
        .help("Cue Track")
        .popover(isPresented: $showingEditor, arrowEdge: .bottom) {
            editorMenu
        }
        .onChange(of: showingEditor) { _, isShowing in
            guard !isShowing else { return }
            commitUndoIfNeeded()
        }
    }

    private var editorMenu: some View {
        CueTrackEditorMenu(
            song: song,
            viewModel: viewModel,
            isGenerating: $isGenerating,
            generateError: $generateError,
            onGenerate: generateCues
        )
    }

    private func commitUndoIfNeeded() {
        guard let before = editStartSnapshot else { return }
        let after = captureSnapshot()
        if before != after {
            registerUndo("Generate Cue Track", before, after)
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

    private func generateCues() {
        isGenerating = true
        generateError = nil
        Task { @MainActor in
            do {
                _ = try await CueTrackFileGenerator.generateAndAttach(
                    to: song,
                    context: modelContext,
                    sourceDurationForTrack: { trackID in
                        if let track = song.sortedTracks.first(where: { $0.id == trackID }) {
                            return viewModel.fileDuration(for: track)
                        }
                        return 1
                    }
                )
                viewModel.reloadSongAfterMediaChange()
                closeEditor()
            } catch {
                generateError = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

struct CueTrackEditorMenu: View {
    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    @Binding var isGenerating: Bool
    @Binding var generateError: String?
    let onGenerate: () -> Void

    private var sourceDurationForTrack: (UUID) -> TimeInterval {
        { trackID in
            if let track = song.sortedTracks.first(where: { $0.id == trackID }) {
                return viewModel.fileDuration(for: track)
            }
            return 1
        }
    }

    private var canGenerate: Bool {
        let duration = CueTrackFileGenerator.timelineDuration(
            for: song,
            sourceDurationForTrack: sourceDurationForTrack
        )
        let hasAnnouncements = !CueTrackFileGenerator.scheduledAnnouncements(
            for: song,
            sourceDurationForTrack: sourceDurationForTrack
        ).isEmpty
        return duration > 0 && hasAnnouncements && !isGenerating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cue Track")
                .font(.headline)

            Button {
                onGenerate()
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(CueTrackFileGenerator.hasCueTrack(in: song) ? "Regenerate Cues" : "Generate Cues")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGenerate)

            if let generateError {
                Text(generateError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Creates an audio track that speaks each section name one measure before it starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 280)
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
            _ = try ClickTrackFileGenerator.generateAndAttach(
                to: song,
                context: modelContext,
                sourceDurationForTrack: { trackID in
                    if let track = song.sortedTracks.first(where: { $0.id == trackID }) {
                        return viewModel.fileDuration(for: track)
                    }
                    return 1
                }
            )
            viewModel.reloadSongAfterMediaChange()
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
        let duration = ClickTrackFileGenerator.timelineDuration(
            for: song,
            sourceDurationForTrack: { trackID in
                if let track = song.sortedTracks.first(where: { $0.id == trackID }) {
                    return viewModel.fileDuration(for: track)
                }
                return 1
            }
        )
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
