#if os(macOS)
import SwiftUI

extension LiveLibrarySidebar {
    func folder(id: UUID) -> SongFolder? {
        folders.first { $0.id == id }
    }

    func setlist(id: UUID) -> Setlist? {
        setlists.first { $0.id == id }
    }

    /// Starts renaming a folder or setlist in place. Returns false for rows that can't be renamed.
    @discardableResult
    func beginRename(of item: Item, currentName: String? = nil) -> Bool {
        let name: String?
        switch item {
        case .allSongs: name = nil
        case .folder(let id): name = currentName ?? folder(id: id)?.name
        case .setlist(let id): name = currentName ?? setlist(id: id)?.name
        }
        guard let name else { return false }
        renameText = name
        renamingItem = item
        return true
    }

    func commitRename(of item: Item) {
        guard renamingItem == item else { return }
        renamingItem = nil
        do {
            switch item {
            case .allSongs:
                break
            case .folder(let id):
                if let folder = folder(id: id) {
                    try SongFolderStore.rename(folder, to: renameText, context: modelContext)
                }
            case .setlist(let id):
                if let setlist = setlist(id: id) {
                    try SetlistLibraryStore.rename(setlist, to: renameText, context: modelContext)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFolder() {
        do {
            let folder = try SongFolderStore.create(
                existingNames: Set(folders.map(\.name)),
                context: modelContext
            )
            selection = .folder(folder.id)
            beginRename(of: .folder(folder.id), currentName: folder.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSetlist() {
        guard let id = onNewSetlist() else { return }
        selection = .setlist(id)
        beginRename(of: .setlist(id), currentName: Setlist.untitledName)
    }

    func duplicate(_ setlist: Setlist) {
        do {
            let copy = try SetlistLibraryStore.duplicate(
                setlist,
                existingNames: Set(setlists.map(\.name)),
                context: modelContext
            )
            beginRename(of: .setlist(copy.id), currentName: copy.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmDelete(_ item: Item) {
        itemPendingDelete = nil
        switch item {
        case .allSongs:
            break
        case .folder(let id):
            guard let folder = folder(id: id) else { return }
            if selection == item {
                selection = .allSongs
            }
            do {
                try SongFolderStore.delete(folder, context: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .setlist(let id):
            guard let setlist = setlist(id: id) else { return }
            onDeleteSetlist(setlist)
        }
    }

    /// Dropping on a folder moves songs into it; dropping on All Songs takes them out of folders.
    func moveDroppedSongs(_ payloads: [String], to folder: SongFolder?) -> Bool {
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

    var deleteConfirmationTitle: String {
        switch itemPendingDelete {
        case .setlist: "Delete Setlist?"
        default: "Delete Folder?"
        }
    }

    var deleteConfirmationMessage: String {
        switch itemPendingDelete {
        case .folder(let id):
            let name = folder(id: id)?.name ?? "This folder"
            return "\"\(name)\" will be deleted. Its songs stay in All Songs."
        case .setlist(let id):
            guard let setlist = setlist(id: id) else { return "" }
            let base = "\"\(displayName(for: setlist))\" will be deleted. Its songs stay in your library."
            if let path = setlist.showFilePath,
               SetlistLibraryStore.isManagedShowFile(URL(fileURLWithPath: path)) {
                return base + " Its show file will be removed."
            }
            return base
        case .allSongs, nil:
            return ""
        }
    }

    /// Attaches the delete confirmation and error alert.
    func sidebarDialogs<Content: View>(on content: Content) -> some View {
        content
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: Binding(
                    get: { itemPendingDelete != nil },
                    set: { if !$0 { itemPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: itemPendingDelete
            ) { item in
                Button(deleteButtonTitle(for: item), role: .destructive) {
                    confirmDelete(item)
                }
            } message: { _ in
                Text(deleteConfirmationMessage)
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

    private func deleteButtonTitle(for item: Item) -> String {
        if case .setlist = item { return "Delete Setlist" }
        return "Delete Folder"
    }
}
#endif
