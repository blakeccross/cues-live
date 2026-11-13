import SwiftUI

/// Window toolbar for the live setlist. The playing song, transport, mixer, and editor
/// live in the floating now-playing bar instead.
struct LiveSetlistToolbarContent<Switcher: View>: ToolbarContent {
    @ViewBuilder let setlistSwitcher: Switcher
    @Binding var showingManageOutputs: Bool
    /// iOS only: toggles drag-to-reorder. `nil` when there is nothing to edit.
    var isEditingSetlist: Binding<Bool>?
    let onAddHeader: () -> Void
    let onAddSong: () -> Void

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            addMenu
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            InputMappingToolbarMenu()
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
            InputMappingToolbarMenu()
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
