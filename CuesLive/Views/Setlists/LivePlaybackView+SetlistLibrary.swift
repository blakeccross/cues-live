import SwiftUI

/// Rename, duplicate, and delete for the active setlist, offered from the setlist title menu.
extension LivePlaybackView {
    func beginRenamingActiveSetlist() {
        guard let activeSetlist else { return }
        setlistRenameText = activeSetlist.name
        isRenamingSetlist = true
    }

    /// Copies the active setlist and switches to the copy.
    func duplicateActiveSetlist() {
        guard let activeSetlist else { return }
        do {
            let copy = try SetlistLibraryStore.duplicate(
                activeSetlist,
                existingNames: Set(allSetlists.map(\.name)),
                context: modelContext
            )
            switchToSetlist(copy)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    /// Attaches the rename prompt and the delete confirmation.
    func setlistLibraryDialogs<Content: View>(on content: Content) -> some View {
        content
            .alert("Rename Setlist", isPresented: $isRenamingSetlist) {
                TextField("Name", text: $setlistRenameText)
                Button("Rename", action: renameActiveSetlist)
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete Setlist?",
                isPresented: $isConfirmingSetlistDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Setlist", role: .destructive, action: deleteActiveSetlist)
            } message: {
                Text(deleteConfirmationMessage)
            }
    }

    private func renameActiveSetlist() {
        guard let activeSetlist else { return }
        do {
            try SetlistLibraryStore.rename(activeSetlist, to: setlistRenameText, context: modelContext)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    /// Moves playback to another setlist before deleting the active one, creating an
    /// untitled setlist when it was the last.
    private func deleteActiveSetlist() {
        guard let setlist = activeSetlist else { return }
        if let replacement = allSetlists.first(where: { $0.id != setlist.id }) {
            switchToSetlist(replacement)
        } else {
            createUntitledSetlist()
        }
        do {
            try SetlistLibraryStore.delete(setlist, context: modelContext)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private var deleteConfirmationMessage: String {
        guard let setlist = activeSetlist else { return "" }
        let base = "\"\(setlistDisplayName(for: setlist))\" will be deleted. Its songs stay in your library."
        if let path = setlist.showFilePath,
           SetlistLibraryStore.isManagedShowFile(URL(fileURLWithPath: path)) {
            return base + " Its show file will be removed."
        }
        return base
    }
}
