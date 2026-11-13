#if os(macOS)
import SwiftUI

extension LivePlaybackView {
    var librarySidebar: some View {
        LiveLibrarySidebar(
            selection: sidebarSelectionBinding,
            onNewSetlist: {
                createUntitledSetlist()
                return activeSetlistID
            },
            onDeleteSetlist: deleteSetlist
        )
    }

    /// Moves playback to another setlist before deleting the active one, creating an
    /// untitled setlist when it was the last.
    private func deleteSetlist(_ setlist: Setlist) {
        if setlist.id == activeSetlist?.id {
            if let replacement = allSetlists.first(where: { $0.id != setlist.id }) {
                switchToSetlist(replacement)
            } else {
                createUntitledSetlist()
            }
        }
        do {
            try SetlistLibraryStore.delete(setlist, context: modelContext)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    /// The songs to list beside the sidebar, or nil when a setlist is selected and the list is closed.
    var libraryScope: SongLibraryScope? {
        switch sidebarSelection {
        case .allSongs:
            return .allSongs
        case .folder(let id):
            return songFolders.first(where: { $0.id == id }).map(SongLibraryScope.folder) ?? .allSongs
        case .setlist, nil:
            return nil
        }
    }

    /// Selecting a setlist closes the song list and makes that setlist the one playing.
    private var sidebarSelectionBinding: Binding<LiveLibrarySidebar.Item?> {
        Binding(
            get: { sidebarSelection },
            set: { item in
                sidebarSelection = item
                if case .setlist(let id) = item,
                   let setlist = allSetlists.first(where: { $0.id == id }) {
                    switchToSetlist(setlist)
                }
            }
        )
    }

    /// Keeps a selected setlist row on the active setlist when it changes elsewhere,
    /// such as from the title menu or File ▸ Open.
    func syncSidebarSelection(toActiveSetlist id: UUID?) {
        guard case .setlist = sidebarSelection, let id else { return }
        sidebarSelection = .setlist(id)
    }

    /// Opens All Songs when the user asks to add a song while the list is closed.
    func revealSongLibrary() {
        if libraryScope == nil {
            sidebarSelection = .allSongs
        }
    }
}
#endif
