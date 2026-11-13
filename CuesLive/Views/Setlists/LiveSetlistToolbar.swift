import SwiftUI

/// Trailing setlist actions in the live window toolbar. Transport, the playing song, and
/// the mixer and editor toggles come from `LiveSetlistTransportToolbarContent`.
struct LiveSetlistToolbarContent<Switcher: View>: ToolbarContent {
    @ViewBuilder let setlistSwitcher: Switcher
    @Binding var showingManageOutputs: Bool
    /// iOS only: toggles drag-to-reorder. `nil` when there is nothing to edit.
    var isEditingSetlist: Binding<Bool>?
    let onAddHeader: () -> Void
    let onAddSong: () -> Void
    /// macOS only: whether the song browser pane is showing, and how to toggle it.
    var isSongBrowserShowing = false
    var onToggleSongBrowser: () -> Void = {}

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            addMenu
        }

        ToolbarItem(placement: .automatic) {
            songBrowserToggle
        }

        ToolbarItem(placement: .automatic) {
            InputMappingToolbarButton()
        }

        ToolbarItem(placement: .automatic) {
            settingsButton
        }
        #else
        ToolbarItem(placement: .topBarLeading) {
            setlistSwitcher
        }

        if let isEditingSetlist {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditingSetlist.wrappedValue ? "Done" : "Edit") {
                    withAnimation { isEditingSetlist.wrappedValue.toggle() }
                }
                .accessibilityLabel(isEditingSetlist.wrappedValue ? "Done reordering" : "Edit setlist order")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            addMenu
        }

        ToolbarItem(placement: .topBarTrailing) {
            InputMappingToolbarButton()
        }

        ToolbarItem(placement: .topBarTrailing) {
            manageOutputsButton
        }
        #endif
    }

    private var addMenu: some View {
        Menu {
            Button(action: onAddHeader) {
                Label("Header", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button(action: onAddSong) {
                Label("Song", systemImage: "music.note")
            }
        } label: {
            Label("Add to Setlist", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .help("Add to Setlist")
    }

    #if os(macOS)
    private var songBrowserToggle: some View {
        Toggle(isOn: Binding(get: { isSongBrowserShowing }, set: { _ in onToggleSongBrowser() })) {
            Label("Song Browser", systemImage: "music.note.square.stack")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(isSongBrowserShowing ? "Hide Song Browser" : "Show Song Browser")
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
}
