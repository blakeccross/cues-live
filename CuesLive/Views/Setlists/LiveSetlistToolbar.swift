import SwiftUI

struct LiveSetlistToolbarContent<Switcher: View>: ToolbarContent {
    @ViewBuilder let setlistSwitcher: Switcher
    let coordinator: PlaybackCoordinator
    @Binding var showingManageOutputs: Bool
    @Binding var mixerDetent: LiveGroupMixerDetent

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    #endif

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .principal) {
            LiveToolbarSongTitle(
                title: coordinator.currentSong?.name ?? "",
                upNext: coordinator.nextSong?.name
            )
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            InputMappingToolbarMenu()
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            songEditorWindowButton
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            mixerButton
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            settingsButton
        }
        .cuesHideSharedBackground()
        #else
        ToolbarItem(placement: .topBarLeading) {
            setlistSwitcher
        }

        ToolbarItem(placement: .topBarTrailing) {
            InputMappingToolbarMenu()
        }

        ToolbarItem(placement: .topBarTrailing) {
            mixerButton
        }

        ToolbarItem(placement: .topBarTrailing) {
            manageOutputsButton
        }
        #endif
    }

    #if os(macOS)
    /// Opens the window that edits the playing song alongside the setlist.
    private var songEditorWindowButton: some View {
        Button {
            openWindow(id: SetlistSongEditorWindowID.value)
        } label: {
            Label("Song Editor Window", systemImage: "macwindow.badge.plus")
                .labelStyle(.iconOnly)
        }
        .help("Edit the playing song in a separate window")
    }

    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .help("Settings")
    }
    #else
    private var manageOutputsButton: some View {
        Button {
            showingManageOutputs = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .tint(showingManageOutputs ? AppColors.accent : nil)
        .help("Settings")
    }
    #endif

    private var mixerButton: some View {
        Button {
            #if os(macOS)
            mixerDetent = mixerDetent == .hidden ? .visible : .hidden
            #else
            mixerDetent = .visible
            #endif
        } label: {
            Label("Group Mixer", systemImage: "slider.vertical.3")
                .labelStyle(.iconOnly)
        }
        #if os(macOS)
        .tint(mixerDetent == .visible ? AppColors.accent : nil)
        #endif
        .help("Group Mixer")
    }
}
