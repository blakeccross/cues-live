#if os(macOS)
import SwiftUI

extension LiveLibrarySidebar {
    func setlist(id: UUID) -> Setlist? {
        setlists.first { $0.id == id }
    }

    /// Starts renaming a setlist in place.
    func beginRename(of id: UUID, currentName: String? = nil) {
        guard let name = currentName ?? setlist(id: id)?.name else { return }
        renameText = name
        renamingSetlistID = id
    }

    func commitRename(of id: UUID) {
        guard renamingSetlistID == id else { return }
        renamingSetlistID = nil
        guard let setlist = setlist(id: id) else { return }
        do {
            try SetlistLibraryStore.rename(setlist, to: renameText, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSetlist() {
        guard let id = onNewSetlist() else { return }
        selection = id
        beginRename(of: id, currentName: Setlist.untitledName)
    }

    func duplicate(_ setlist: Setlist) {
        do {
            let copy = try SetlistLibraryStore.duplicate(
                setlist,
                existingNames: Set(setlists.map(\.name)),
                context: modelContext
            )
            beginRename(of: copy.id, currentName: copy.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteConfirmationMessage(for setlist: Setlist) -> String {
        let base = "\"\(displayName(for: setlist))\" will be deleted. Its songs stay in your library."
        if let path = setlist.showFilePath,
           SetlistLibraryStore.isManagedShowFile(URL(fileURLWithPath: path)) {
            return base + " Its show file will be removed."
        }
        return base
    }

    /// Attaches the delete confirmation and error alert.
    func sidebarDialogs<Content: View>(on content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete Setlist?",
                isPresented: Binding(
                    get: { setlistPendingDelete != nil },
                    set: { if !$0 { setlistPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: setlistPendingDelete
            ) { setlist in
                Button("Delete Setlist", role: .destructive) {
                    setlistPendingDelete = nil
                    onDeleteSetlist(setlist)
                }
            } message: { setlist in
                Text(deleteConfirmationMessage(for: setlist))
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
