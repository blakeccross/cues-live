import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MissingMediaRelinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let setlistID: UUID
    /// Snapshot captured when the sheet opens so the list is never blank on first paint.
    let initialMissingTracks: [SongMediaHealth.MissingTrack]
    /// When set, only show missing tracks for this song.
    var focusedSongID: UUID? = nil
    var onChanged: () -> Void = {}

    @State private var missingTracks: [SongMediaHealth.MissingTrack] = []
    @State private var didLoad = false
    @State private var trackPendingRelink: SongMediaHealth.MissingTrack?
    @State private var showingFileImporter = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var groupedMissing: [(songName: String, songID: UUID, tracks: [SongMediaHealth.MissingTrack])] {
        let filtered: [SongMediaHealth.MissingTrack]
        if let focusedSongID {
            filtered = missingTracks.filter { $0.songID == focusedSongID }
        } else {
            filtered = missingTracks
        }

        var order: [UUID] = []
        var buckets: [UUID: [SongMediaHealth.MissingTrack]] = [:]
        var names: [UUID: String] = [:]
        for track in filtered {
            if buckets[track.songID] == nil {
                order.append(track.songID)
                names[track.songID] = track.songName
            }
            buckets[track.songID, default: []].append(track)
        }
        return order.compactMap { songID in
            guard let tracks = buckets[songID], let name = names[songID] else { return nil }
            return (name, songID, tracks)
        }
    }

    var body: some View {
        AppSheetContainer {
            NavigationStack {
                Group {
                    if !didLoad {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if groupedMissing.isEmpty {
                        ContentUnavailableView(
                            "All Files Found",
                            systemImage: "checkmark.circle",
                            description: Text("Every track in this setlist can be located on disk.")
                        )
                    } else {
                        VStack(spacing: 0) {
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.sm)
                            }

                            List {
                                ForEach(groupedMissing, id: \.songID) { group in
                                    Section(group.songName) {
                                        ForEach(group.tracks) { missing in
                                            HStack(alignment: .center, spacing: AppSpacing.sm) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundStyle(AppColors.warning)
                                                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                                                    Text(missing.trackName)
                                                        .foregroundStyle(AppColors.textPrimary)
                                                    Text(missing.expectedFileName)
                                                        .font(AppTypography.caption)
                                                        .foregroundStyle(AppColors.textTertiary)
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 0)
                                                Button("Relink…") {
                                                    trackPendingRelink = missing
                                                    showingFileImporter = true
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                        }
                                    }
                                }
                            }
                            .listStyle(.inset)
                        }
                    }
                }
                .frame(minWidth: 420, minHeight: 320)
                .navigationTitle("Missing Files")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .fileImporter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: FileStore.supportedTypes,
                    allowsMultipleSelection: false
                ) { result in
                    handleRelinkResult(result)
                }
                .alert("Relink Failed", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
                .task {
                    await loadMissingTracks()
                }
            }
        }
    }

    @MainActor
    private func loadMissingTracks() async {
        if missingTracks.isEmpty {
            missingTracks = initialMissingTracks
        }

        do {
            let fresh = try SongMediaHealth.missingTracks(
                forSetlistID: setlistID,
                in: modelContext
            )
            // Prefer a non-empty fresh fetch; fall back to the snapshot if relationships
            // were temporarily unavailable.
            missingTracks = fresh.isEmpty && !initialMissingTracks.isEmpty
                ? initialMissingTracks
                : fresh
        } catch {
            if missingTracks.isEmpty {
                missingTracks = initialMissingTracks
            }
        }

        didLoad = true
        onChanged()
    }

    private func refreshMissing() {
        do {
            missingTracks = try SongMediaHealth.missingTracks(
                forSetlistID: setlistID,
                in: modelContext
            )
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleRelinkResult(_ result: Result<[URL], Error>) {
        let pending = trackPendingRelink
        defer { trackPendingRelink = nil }

        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let fileURL = urls.first,
                  let pending,
                  let song = try? SongMediaHealth.fetchSong(id: pending.songID, in: modelContext)
            else {
                errorMessage = SongMediaHealth.RelinkError.trackNotFound.localizedDescription
                return
            }

            do {
                let outcome = try SongMediaHealth.relink(
                    trackID: pending.trackID,
                    in: song,
                    to: fileURL,
                    context: modelContext
                )
                if outcome.autoLinkedCount > 0 {
                    let auto = outcome.autoLinkedCount
                    statusMessage = auto == 1
                        ? "Relinked this file and auto-linked 1 other by name."
                        : "Relinked this file and auto-linked \(auto) others by name."
                } else {
                    statusMessage = "Relinked \(pending.trackName)."
                }
                refreshMissing()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
