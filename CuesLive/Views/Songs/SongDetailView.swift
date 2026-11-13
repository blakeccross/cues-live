import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SongDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var song: Song

    @State private var viewModel: SongEditorViewModel?
    @State private var showingAbletonImporter = false
    @State private var abletonImportError: String?
    @State private var abletonImportSummary: String?
    @State private var timeline = SongTimeline()
    @State private var tempoChanges: [TempoChange] = []
    @State private var timeSignatureChanges: [TimeSignatureChange] = []
    @State private var midiEvents: [MIDIEvent] = []
    @State private var undoController = SongUndoController()

    var body: some View {
        songDetailContent
            .appBackground(.primary)
            #if os(iOS)
            .navigationTitle(song.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .locksInterfaceOrientations(.landscape)
            #else
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .windowToolbar)
            #endif
            .fileImporter(
                isPresented: $showingAbletonImporter,
                allowedContentTypes: [AbletonProjectImporter.abletonLiveSetType],
                allowsMultipleSelection: false
            ) { result in
                handleAbletonImport(result)
            }
            .alert("Ableton Import Failed", isPresented: Binding(
                get: { abletonImportError != nil },
                set: { if !$0 { abletonImportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(abletonImportError ?? "")
            }
            .alert("Ableton Import Complete", isPresented: Binding(
                get: { abletonImportSummary != nil },
                set: { if !$0 { abletonImportSummary = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(abletonImportSummary ?? "")
            }
            .onAppear(perform: handleAppear)
            .navigationBarBackButtonHidden(true)
            #if os(macOS)
            .focusedValue(\.songEditorActions, songEditorActions)
            .focusedValue(\.songUndoActions, songUndoActions)
            #endif
            .onDisappear {
                AudioEngineManager.shared.stop()
                persistSongState()
            }
    }

    private func attemptDismiss() {
        persistSongState()
        dismiss()
    }

    private var songDetailContent: some View {
        VStack(spacing: 0) {
            if let viewModel {
                ZStack(alignment: .top) {
                    EditView(
                        song: song,
                        viewModel: viewModel,
                        undoController: undoController,
                        timeline: $timeline,
                        tempoChanges: $tempoChanges,
                        timeSignatureChanges: $timeSignatureChanges,
                        midiEvents: $midiEvents,
                        onBack: attemptDismiss
                    )

                    if viewModel.isReloadingSong && viewModel.isLoaded {
                        songLoadingOverlay(for: viewModel)
                    } else if !viewModel.isLoaded && viewModel.loadError == nil {
                        audioLoadingBanner(for: viewModel)
                    }
                }
                .onChange(of: viewModel.isReloadingSong) { wasReloading, isReloading in
                    guard wasReloading, !isReloading else { return }
                    syncArrangementPlayback()
                    syncTempoPlayback()
                }
                .onChange(of: viewModel.isLoaded) { _, isLoaded in
                    guard isLoaded else { return }
                    syncArrangementPlayback()
                    syncTempoPlayback()
                }
            } else {
                ProgressView("Loading song...")
                    .tint(AppColors.accent)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func audioLoadingBanner(for viewModel: SongEditorViewModel) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColors.accent)
            Text("Loading audio…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func songLoadingOverlay(for viewModel: SongEditorViewModel) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .tint(AppColors.accent)
                Text("Loading audio…")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                if let loadError = viewModel.loadError {
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(AppSpacing.xl)
            .background(AppColors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    #if os(macOS)
    private var songEditorActions: SongEditorActions {
        SongEditorActions(
            canAutoGroup: !song.sortedTracks.isEmpty,
            autoGroup: {
                TrackGroupStore.autoAssignGroups(for: song, in: modelContext)
                if viewModel?.song.id == song.id {
                    viewModel?.refreshTrackOutputGroups()
                }
            },
            importAbleton: {
                showingAbletonImporter = true
            }
        )
    }

    private var songUndoActions: SongUndoActions {
        return SongUndoActions(
            canUndo: undoController.canUndo,
            canRedo: undoController.canRedo,
            undoActionName: undoController.undoActionName,
            redoActionName: undoController.redoActionName,
            undo: { undoController.undo() },
            redo: { undoController.redo() }
        )
    }
    #endif

    private func handleAppear() {
        let audioEngine = AudioEngineManager.shared
        audioEngine.pause()
        audioEngine.onPlaybackFinished = nil
        loadEditor(forceReloadViewModel: viewModel?.song.id != song.id)
    }

    private func loadEditor(forceReloadViewModel: Bool) {
        if viewModel == nil || forceReloadViewModel {
            let model = SongEditorViewModel(song: song)
            model.preloadTrackDurations()
            model.loadSong(context: modelContext)
            viewModel = model
        }

        _ = try? SongProjectBridge.ensureProjectFile(for: song, context: modelContext)

        guard let projectState = try? SongProjectBridge.loadProjectState(for: song) else {
            return
        }
        timeline = projectState.timeline
        tempoChanges = projectState.tempoChanges
        timeSignatureChanges = projectState.timeSignatureChanges
        midiEvents = projectState.midiEvents
        syncArrangementPlayback()
        syncTempoPlayback()
    }

    private func persistSongState() {
        try? SongProjectBridge.persist(
            song: song,
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents,
            context: modelContext
        )
    }

    private func syncArrangementPlayback() {
        guard let viewModel else { return }
        viewModel.syncArrangement(timeline)
    }

    private func syncTempoPlayback() {
        guard let viewModel else { return }
        viewModel.syncTempoMap(tempoChanges, timeSignatureChanges: timeSignatureChanges)
    }

    private func handleAbletonImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            abletonImportError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let importResult = try AbletonProjectImporter.importFrom(url: url)
                let markers = AbletonProjectImporter.makeMarkers(from: importResult).sortedByTime
                if !markers.isEmpty {
                    timeline.markers = markers
                }
                try AbletonProjectImporter.apply(
                    importResult,
                    markers: markers,
                    to: song,
                    context: modelContext
                )
                tempoChanges = [TempoChange(startMeasure: 1, bpm: importResult.bpm, sortOrder: 0)]
                timeSignatureChanges = importResult.timeSignatures
                persistSongState()
                abletonImportSummary = importSummary(for: importResult)
                syncArrangementPlayback()
                syncTempoPlayback()
            } catch {
                abletonImportError = error.localizedDescription
            }
        }
    }

    private func importSummary(for result: AbletonProjectImporter.ImportResult) -> String {
        let bpmText = String(format: "%.1f BPM", result.bpm)
        var message: String
        if result.sections.isEmpty {
            message = "Imported tempo at \(bpmText)."
        } else {
            message = "Imported \(result.sections.count) sections at \(bpmText)."
        }
        let signatures = result.timeSignatures.sortedByMeasure
        if signatures.count == 1, let initial = signatures.first {
            message += " Time signature: \(initial.displayName)."
        } else if signatures.count > 1 {
            let summary = signatures.prefix(3).map { signature in
                if signature.startMeasure == 1 {
                    return signature.displayName
                }
                return "\(signature.displayName) at measure \(signature.startMeasure)"
            }.joined(separator: ", ")
            message += " Time signatures: \(summary)"
            if signatures.count > 3 {
                message += ", …"
            }
            message += "."
        }
        if !result.sections.isEmpty {
            let sectionLines = result.sections.prefix(4).map { section in
                "\(section.name) at \(formatMarkerTime(section.startSeconds))"
            }
            let extraCount = max(0, result.sections.count - 4)
            message += "\n"
            message += sectionLines.joined(separator: "\n")
            if extraCount > 0 {
                message += "\n…and \(extraCount) more."
            }
        }
        return message
    }

    private func formatMarkerTime(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        SongDetailView(song: Song(name: "Preview"))
    }
}
