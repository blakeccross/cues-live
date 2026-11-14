import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TrackImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let song: Song
    let onError: (String) -> Void

    @State private var showingImporter = true
    @State private var showingFolderImporter = false
    @State private var importedCount = 0
    @State private var importedSectionCount = 0

    var body: some View {
        AppSheetContainer {
            NavigationStack {
                VStack(spacing: AppSpacing.md) {
                    Text("Import stems for \(song.name)")
                        .appTitle()

                    if importedCount > 0 {
                        Text("\(importedCount) track\(importedCount == 1 ? "" : "s") imported")
                            .appCaptionText()
                        if importedSectionCount > 0 {
                            Text("\(importedSectionCount) Ableton section\(importedSectionCount == 1 ? "" : "s") imported")
                                .appCaptionText()
                        }
                    } else {
                        Text("Select audio files or a folder containing a Multitracks subfolder and an optional Ableton file.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }

                    AppPrimaryButton(title: "Choose Files") {
                        showingImporter = true
                    }

                    AppSecondaryButton(title: "Choose Folder") {
                        showingFolderImporter = true
                    }

                    if importedCount > 0 {
                        AppSecondaryButton(title: "Done") {
                            dismiss()
                        }
                    }
                }
                .padding(AppSpacing.lg)
                .navigationTitle("Import Tracks")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .fileImporter(
                    isPresented: $showingImporter,
                    allowedContentTypes: FileStore.supportedTypes,
                    allowsMultipleSelection: true
                ) { result in
                    handleImport(result)
                }
                .fileImporter(
                    isPresented: $showingFolderImporter,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    handleFolderImport(result)
                }
                .onAppear {
                    #if os(iOS)
                    showingImporter = true
                    #endif
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            onError(error.localizedDescription)
        case .success(let urls):
            guard !urls.isEmpty else { return }
            do {
                let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: modelContext)
                let tracks = try FileStore.linkTracks(
                    from: urls,
                    into: song,
                    projectFileURL: projectURL
                )
                for track in tracks {
                    modelContext.insert(track)
                    song.tracks.append(track)
                }
                try modelContext.save()
                try SongProjectBridge.syncProjectFile(for: song, context: modelContext)
                importedCount += tracks.count
                TrackGroupStore.autoAssignGroups(for: song, in: modelContext)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            onError(error.localizedDescription)
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            do {
                let importResult = try SongFolderImporter.importIntoExistingSong(
                    at: folderURL,
                    song: song,
                    context: modelContext
                )
                importedCount += importResult.trackCount
                importedSectionCount += importResult.sectionCount
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}

#Preview {
    TrackImportView(song: Song(name: "Demo")) { _ in }
        .modelContainer(for: [Song.self, AudioTrack.self], inMemory: true)
}
