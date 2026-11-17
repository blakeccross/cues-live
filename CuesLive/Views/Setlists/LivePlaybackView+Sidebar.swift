#if os(macOS)
import SwiftUI

extension LivePlaybackView {
    /// The leading pane: song folders beside the selected folder's songs.
    var songBrowser: some View {
        LiveSongBrowser(folderSelection: $songBrowserFolder) {
            songLibraryPanel(scope: songBrowserScope)
        }
    }

    private var songBrowserScope: SongLibraryScope {
        guard case .folder(let id) = songBrowserFolder,
              let folder = songFolders.first(where: { $0.id == id }) else {
            return .allSongs
        }
        return .folder(folder)
    }

    /// Whether the song browser is showing. Mapping hides it to leave room for the inspector.
    var isSongBrowserShowing: Bool {
        isSongBrowserVisible && !mapping.isMapping
    }

    /// Shows or hides the song browser. Showing it ends any mapping session.
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
