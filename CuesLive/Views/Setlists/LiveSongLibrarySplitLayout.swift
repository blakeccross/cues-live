import SwiftUI

/// Persists whether the song library pane is open so it survives navigating to the
/// song editor and relaunches. On iOS the library is a sheet and always starts closed.
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
/// Places the song library in a resizable pane beside the setlist, below the waveform.
struct LiveSongLibrarySplitLayout<Library: View, SetlistContent: View>: View {
    let isLibraryVisible: Bool
    @ViewBuilder let library: () -> Library
    @ViewBuilder let setlist: () -> SetlistContent

    var body: some View {
        HSplitView {
            if isLibraryVisible {
                library()
                    .background(AppColors.backgroundSecondary)
                    .frame(
                        minWidth: LivePlaybackSidebarMetrics.minimumSidebarWidth,
                        idealWidth: LivePlaybackSidebarMetrics.defaultSidebarWidth,
                        maxWidth: LivePlaybackSidebarMetrics.maximumSidebarWidth
                    )
            }

            setlist()
                .frame(minWidth: LivePlaybackSidebarMetrics.minimumMainWidth)
        }
        .onChange(of: isLibraryVisible) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: SongLibraryPanePreference.storageKey)
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
