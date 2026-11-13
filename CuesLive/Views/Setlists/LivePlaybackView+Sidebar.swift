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

    /// Follows the active setlist, so switching from the title menu or File ▸ Open moves the
    /// selection too. Selecting a row makes that setlist the one playing.
    private var sidebarSelectionBinding: Binding<UUID?> {
        Binding(
            get: { activeSetlist?.id },
            set: { id in
                guard let setlist = allSetlists.first(where: { $0.id == id }) else { return }
                switchToSetlist(setlist)
            }
        )
    }

    /// The mapping inspector takes the trailing pane while mapping; otherwise the song browser does.
    @ViewBuilder
    var trailingPane: some View {
        if mapping.isMapping {
            InputMappingPanel()
        } else {
            LiveSongBrowser(folderSelection: $songBrowserFolder) {
                songLibraryPanel(scope: songBrowserScope)
            }
        }
    }

    var trailingPaneMinimumWidth: CGFloat {
        mapping.isMapping ? LivePlaybackSidebarMetrics.minimumSidebarWidth : LiveSongBrowser<EmptyView>.minimumWidth
    }

    private var songBrowserScope: SongLibraryScope {
        guard case .folder(let id) = songBrowserFolder,
              let folder = songFolders.first(where: { $0.id == id }) else {
            return .allSongs
        }
        return .folder(folder)
    }

    /// Whether the song browser is the pane showing, rather than hidden or covered by mapping.
    var isSongBrowserShowing: Bool {
        isSongBrowserVisible && !mapping.isMapping
    }

    /// Shows or hides the song browser. Showing it ends any mapping session, which shares the pane.
    func toggleSongBrowser() {
        if isSongBrowserShowing {
            isSongBrowserVisible = false
        } else {
            revealSongLibrary()
        }
    }

    /// Opens the song browser when the user asks to add a song.
    func revealSongLibrary() {
        if mapping.isMapping {
            mapping.endMapping()
        }
        isSongBrowserVisible = true
    }
}
#endif
