#if os(macOS)
import SwiftUI

/// The live window's song browser, opened from the toolbar like Logic Pro's Browser pane:
/// song folders in a narrow column on the left, the selected folder's songs on the right.
@MainActor
struct LiveSongBrowser<Songs: View>: View {
    static var minimumWidth: CGFloat { folderColumnWidth + LivePlaybackSidebarMetrics.minimumSidebarWidth }
    private static var folderColumnWidth: CGFloat { 180 }

    @Binding var folderSelection: LiveSongFolderList.Item?
    @ViewBuilder let songs: () -> Songs

    var body: some View {
        HStack(spacing: 0) {
            LiveSongFolderList(selection: retainedFolderSelection)
                .frame(width: Self.folderColumnWidth)

            Divider()

            songs()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.backgroundSecondary)
    }

    /// The sidebar list writes `nil` when it leaves the window, such as while the song editor
    /// is pushed over the live view. Ignoring those writes keeps the folder selected on return.
    private var retainedFolderSelection: Binding<LiveSongFolderList.Item?> {
        Binding {
            folderSelection
        } set: { newSelection in
            guard let newSelection else { return }
            folderSelection = newSelection
        }
    }
}
#endif
