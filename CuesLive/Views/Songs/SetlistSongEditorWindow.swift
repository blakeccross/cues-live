#if os(macOS)
import SwiftData
import SwiftUI

enum SetlistSongEditorWindowID {
    static let value = "setlist-song-editor"
}

/// Separate window that edits whichever song the live setlist has active,
/// following it from song to song while the setlist plays, or a song sent to it from Edit.
@MainActor
struct SetlistSongEditorWindow: View {
    @Bindable private var link = SetlistEditorLink.shared
    @Query private var songs: [Song]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("")
        }
        .appBackground(.primary)
        .onAppear { link.setWindowOpen(true) }
        .onDisappear { link.setWindowOpen(false) }
    }

    /// The pinned song when there is one, otherwise the setlist's active song.
    private func displayedSong(in coordinator: PlaybackCoordinator) -> Song? {
        if let pinnedSongID = link.pinnedSongID,
           let pinned = songs.first(where: { $0.id == pinnedSongID }) {
            return pinned
        }
        return coordinator.currentSong
    }

    @ViewBuilder
    private var content: some View {
        if link.isInlineEditorOpen {
            AppEmptyState(
                title: "Song Editor Open in Main Window",
                systemImage: "rectangle.badge.plus",
                description: "Close the song editor in the main window to edit the setlist’s song here."
            )
        } else if let coordinator = link.followableCoordinator {
            if let song = displayedSong(in: coordinator) {
                SetlistSongEditorHost(song: song, coordinator: coordinator)
                    .id(song.id)
            } else {
                AppEmptyState(
                    title: "No Song",
                    systemImage: "music.note.list",
                    description: "Add a song to the setlist to edit it here."
                )
            }
        } else {
            AppEmptyState(
                title: "No Setlist Open",
                systemImage: "music.note.list",
                description: "Open a setlist in the main window. This window edits the song it is playing."
            )
        }
    }
}
#endif
