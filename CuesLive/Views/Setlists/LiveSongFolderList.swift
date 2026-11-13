#if os(macOS)
import SwiftData
import SwiftUI

/// The folder column of the song browser: All Songs above the user's song folders. Folders
/// rename in place (Return or Rename…), delete with the Delete key or the context menu, and take
/// songs dragged onto them.
@MainActor
struct LiveSongFolderList: View {
    enum Item: Hashable {
        case allSongs
        case folder(UUID)
    }

    @Binding var selection: Item?

    @Environment(\.modelContext) private var modelContext
    @Query private var songs: [Song]
    @Query private var folders: [SongFolder]

    @State private var renamingFolderID: UUID?
    @State private var renameText = ""
    @State private var folderPendingDelete: SongFolder?
    @State private var errorMessage: String?
    @FocusState private var isRenameFieldFocused: Bool

    private var sortedFolders: [SongFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        folderDialogs(on: folderList)
    }

    private var folderList: some View {
        List(selection: $selection) {
            Label("All Songs", systemImage: "music.note.house")
                .badge(songs.count)
                .tag(Item.allSongs)
                .dropDestination(for: String.self) { payloads, _ in
                    moveDroppedSongs(payloads, to: nil)
                }

            ForEach(sortedFolders) { folder in
                folderRow(folder)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onKeyPress(.return) {
            guard renamingFolderID == nil, case .folder(let id) = selection else { return .ignored }
            beginRename(of: id)
            return .handled
        }
        .onDeleteCommand {
            guard renamingFolderID == nil, case .folder(let id) = selection else { return }
            folderPendingDelete = folders.first { $0.id == id }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            newFolderButton
        }
    }

    private func folderRow(_ folder: SongFolder) -> some View {
        Label {
            if renamingFolderID == folder.id {
                TextField("Name", text: $renameText)
                    .focused($isRenameFieldFocused)
                    .onSubmit { commitRename(of: folder) }
                    .onExitCommand { renamingFolderID = nil }
                    .onChange(of: isRenameFieldFocused) { _, isFocused in
                        if !isFocused { commitRename(of: folder) }
                    }
                    .task { isRenameFieldFocused = true }
            } else {
                Text(folder.name)
            }
        } icon: {
            Image(systemName: "folder")
        }
        .badge(folder.songs.count)
        .tag(Item.folder(folder.id))
        .dropDestination(for: String.self) { payloads, _ in
            moveDroppedSongs(payloads, to: folder)
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                beginRename(of: folder.id)
            }
            Divider()
            Button("Delete Folder…", systemImage: "trash", role: .destructive) {
                folderPendingDelete = folder
            }
        }
    }

    private var newFolderButton: some View {
        Button(action: createFolder) {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .help("New song folder")
    }

    private func beginRename(of id: UUID, currentName: String? = nil) {
        guard let name = currentName ?? folders.first(where: { $0.id == id })?.name else { return }
        renameText = name
        renamingFolderID = id
    }

    private func commitRename(of folder: SongFolder) {
        guard renamingFolderID == folder.id else { return }
        renamingFolderID = nil
        do {
            try SongFolderStore.rename(folder, to: renameText, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFolder() {
        do {
            let folder = try SongFolderStore.create(
                existingNames: Set(folders.map(\.name)),
                context: modelContext
            )
            selection = .folder(folder.id)
            beginRename(of: folder.id, currentName: folder.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ folder: SongFolder) {
        folderPendingDelete = nil
        if selection == .folder(folder.id) {
            selection = .allSongs
        }
        do {
            try SongFolderStore.delete(folder, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Dropping on a folder moves songs into it; dropping on All Songs takes them out of folders.
    private func moveDroppedSongs(_ payloads: [String], to folder: SongFolder?) -> Bool {
        let ids = Set(payloads.compactMap(SongDragPayload.songID(from:)))
        let dropped = songs.filter { ids.contains($0.id) }
        guard !dropped.isEmpty else { return false }
        do {
            try SongFolderStore.move(dropped, to: folder, context: modelContext)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func folderDialogs<Content: View>(on content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete Folder?",
                isPresented: Binding(
                    get: { folderPendingDelete != nil },
                    set: { if !$0 { folderPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: folderPendingDelete
            ) { folder in
                Button("Delete Folder", role: .destructive) {
                    delete(folder)
                }
            } message: { folder in
                Text("\"\(folder.name)\" will be deleted. Its songs stay in All Songs.")
            }
            .alert("Could Not Update Library", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
#endif
