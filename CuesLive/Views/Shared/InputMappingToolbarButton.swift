import SwiftUI

/// Toolbar toggle that shows or hides the mapping inspector. The inspector's own tabs
/// choose between key and MIDI mapping.
@MainActor
struct InputMappingToolbarButton: View {
    @Environment(InputMappingController.self) private var mapping

    var body: some View {
        Toggle(isOn: isShowingInspector) {
            Label("Mapping", systemImage: "keyboard")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(mapping.isMapping ? "Hide Mapping" : "Show Mapping")
        .accessibilityLabel("Key and MIDI Mapping")
    }

    private var isShowingInspector: Binding<Bool> {
        Binding(
            get: { mapping.isMapping },
            set: { isOn in
                guard isOn != mapping.isMapping else { return }
                mapping.toggleMapping()
            }
        )
    }
}
