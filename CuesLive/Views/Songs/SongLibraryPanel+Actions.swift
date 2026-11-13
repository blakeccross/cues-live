import SwiftData
import SwiftUI

extension SongLibraryPanel {
    @ViewBuilder
    func songContextMenu(for ids: Set<UUID>) -> some View {
        let targets = songs(for: ids)
        if targets.count == 1, let song = targets.first {
            Button("Edit Song", systemImage: "pencil") {
                onEdit(song)
            }
            Button("Add to Setlist", systemImage: "text.badge.plus") {
                onAddToSetlist(song)
            }
            Divider()
            Button("Rename…", systemImage: "character.cursor.ibeam") {
                songPendingRename = song
                renameSongName = song.name
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                duplicateSong(song)
            }
            if SongProjectBridge.projectURL(for: song) != nil {
                Button("Consolidate Media…", systemImage: "shippingbox") {
                    consolidateMedia(for: song)
                }
            }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) {
                songsPendingDelete = [song]
            }
        } else if targets.count > 1 {
            Button("Add \(targets.count) Songs to Setlist", systemImage: "text.badge.plus") {
                addToSetlist(targets)
            }
            Divider()
            Button("Delete \(targets.count) Songs…", systemImage: "trash", role: .destructive) {
                songsPendingDelete = targets
            }
        }
    }

    func addToSetlist(_ songs: [Song]) {
        songs.forEach(onAddToSetlist)
    }

    func requestDeleteSelection() {
        let selected = songs(for: selection)
        guard !selected.isEmpty else { return }
        songsPendingDelete = selected
    }

    /// Attaches the alerts, confirmations, and sheets the library's actions present.
    func songActionDialogs<Content: View>(on content: Content) -> some View {
        content
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: Binding(
                    get: { !songsPendingDelete.isEmpty },
                    set: { if !$0 { songsPendingDelete = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button(songsPendingDelete.count == 1 ? "Delete Song" : "Delete \(songsPendingDelete.count) Songs", role: .destructive) {
                    deleteSongs(songsPendingDelete)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteConfirmationMessage)
            }
            .alert("Rename Song", isPresented: Binding(
                get: { songPendingRename != nil },
                set: { if !$0 { songPendingRename = nil } }
            )) {
                TextField("Song name", text: $renameSongName)
                Button("Rename", action: renameSong)
                Button("Cancel", role: .cancel) {
                    songPendingRename = nil
                }
            }
            .alert("Could Not Create Song", isPresented: presenceBinding($createSongError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(createSongError ?? "")
            }
            .alert("Could Not Update Song", isPresented: presenceBinding($songActionError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(songActionError ?? "")
            }
            .alert("Media Consolidated", isPresented: presenceBinding($consolidateSummary)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(consolidateSummary ?? "")
            }
            .sheet(isPresented: $showingAddClickSheet) {
                AddClickSongSheet { name, bpm, numerator, denominator in
                    createClickSong(name: name, bpm: bpm, numerator: numerator, denominator: denominator)
                }
            }
            .sheet(item: $folderSetupSession) { session in
                SongFolderSetupSheet(previews: session.previews) { requests in
                    folderSetupSession = nil
                    guard !requests.isEmpty else { return }
                    onFoldersSelected(requests)
                }
            }
            #if os(iOS)
            .fileImporter(
                isPresented: $showingFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderSelection(result)
            }
            #endif
    }

    private var deleteConfirmationTitle: String {
        songsPendingDelete.count == 1 ? "Delete Song?" : "Delete \(songsPendingDelete.count) Songs?"
    }

    private var deleteConfirmationMessage: String {
        if songsPendingDelete.count == 1, let song = songsPendingDelete.first {
            return "\"\(song.name)\" and its tracks will be permanently deleted and removed from any setlists."
        }
        return "These songs and their tracks will be permanently deleted and removed from any setlists."
    }

    private func presenceBinding(_ message: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )
    }

    private func deleteSongs(_ targets: [Song]) {
        let ids = Set(targets.map(\.id))
        songsPendingDelete = []
        do {
            try SongLibraryStore.delete(targets, context: modelContext)
            selection.subtract(ids)
            #if os(iOS)
            if songs.isEmpty {
                editMode = .inactive
            }
            #endif
        } catch {
            songActionError = error.localizedDescription
        }
    }

    private func createClickSong(name: String, bpm: Double, numerator: Int, denominator: Int) {
        do {
            let song = try ClickSongCreator.create(
                name: name,
                bpm: bpm,
                numerator: numerator,
                denominator: denominator,
                context: modelContext
            )
            showingAddClickSheet = false
            onEdit(song)
        } catch {
            createSongError = error.localizedDescription
        }
    }

    private func renameSong() {
        let trimmed = renameSongName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let song = songPendingRename, !trimmed.isEmpty else {
            songPendingRename = nil
            return
        }

        song.name = trimmed
        do {
            try modelContext.save()
            try SongProjectBridge.syncProjectFile(for: song, context: modelContext)
            songPendingRename = nil
        } catch {
            songActionError = error.localizedDescription
        }
    }

    private func duplicateSong(_ source: Song) {
        do {
            try SongLibraryStore.duplicate(source, existingNames: Set(songs.map(\.name)), context: modelContext)
        } catch {
            songActionError = error.localizedDescription
        }
    }

    private func consolidateMedia(for song: Song) {
        do {
            let stemsDirectory = try MediaConsolidator.consolidate(for: song, context: modelContext)
            consolidateSummary = "Copied media to \(stemsDirectory.path)."
        } catch {
            songActionError = error.localizedDescription
        }
    }
}
