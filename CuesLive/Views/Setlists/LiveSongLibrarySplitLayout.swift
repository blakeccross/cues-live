import SwiftUI

/// Persists whether the remote session's song library pane is open so it survives navigating
/// to the song editor and relaunches. The local live view uses `LiveSongBrowser`
/// instead. On iOS the library is a sheet and always starts closed.
enum SongLibraryPanePreference {
    static let storageKey = "songSidebarVisible"

    static var initialVisibility: Bool {
        #if os(macOS)
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
        #else
        false
        #endif
    }
}

#if os(macOS)
/// Places the song library in a resizable pane beside the setlist. A plain stack rather than
/// a split view, so the window's bottom safe area reaches both panes. When the pane touches
/// the top of the window, its background and divider run up under the toolbar like a column.
struct LiveSongLibrarySplitLayout<Library: View, SetlistContent: View>: View {
    let isLibraryVisible: Bool
    @ViewBuilder let library: () -> Library
    @ViewBuilder let setlist: () -> SetlistContent

    @State private var libraryWidth = LivePlaybackSidebarMetrics.defaultSidebarWidth
    @State private var totalWidth: CGFloat = .greatestFiniteMagnitude

    var body: some View {
        HStack(spacing: 0) {
            if isLibraryVisible {
                library()
                    .background(AppColors.backgroundSecondary.ignoresSafeArea(edges: .top))
                    .frame(width: LivePlaybackSidebarMetrics.clampedSidebarWidth(libraryWidth, totalWidth: totalWidth))

                AppResizableDivider(
                    length: $libraryWidth,
                    edge: .trailing,
                    clamp: { LivePlaybackSidebarMetrics.clampedSidebarWidth($0, totalWidth: totalWidth) },
                    accessibilityLabel: "Song library width"
                )
                .ignoresSafeArea(edges: .top)
                .zIndex(1)
            }

            setlist()
                .frame(minWidth: LivePlaybackSidebarMetrics.minimumMainWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.none, value: libraryWidth)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            totalWidth = width
        }
    }
}

/// Toolbar button that shows or hides the song library pane.
struct SongLibraryToggleButton: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Label("Songs", systemImage: "music.note.list")
                .labelStyle(.iconOnly)
        }
        .tint(isVisible ? AppColors.accent : nil)
        .help(isVisible ? "Hide Songs" : "Show Songs")
    }
}
#endif
