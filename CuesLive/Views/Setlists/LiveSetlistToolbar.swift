import SwiftUI

struct LiveSetlistToolbarContent<Switcher: View>: ToolbarContent {
    @ViewBuilder let setlistSwitcher: Switcher
    let coordinator: PlaybackCoordinator
    @Binding var showingSongLibrary: Bool
    @Binding var showingManageOutputs: Bool
    @Binding var mixerDetent: LiveGroupMixerDetent

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            songsButton
        }
        .cuesHideSharedBackground()

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

    private var songsButton: some View {
        Button {
            showingSongLibrary.toggle()
        } label: {
            Label("Songs", systemImage: "music.note.list")
                .labelStyle(.iconOnly)
        }
        .tint(showingSongLibrary ? AppColors.accent : nil)
        .help("Songs")
    }

    #if os(macOS)
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

#if os(macOS)
struct LivePlaybackMacToolbarBackgroundVisibilityModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}
#endif
