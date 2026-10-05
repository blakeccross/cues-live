#if os(iOS)
import SwiftUI

struct DeviceSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onRoutingChanged: (() -> Void)? = nil

    init(onRoutingChanged: (() -> Void)? = nil) {
        self.onRoutingChanged = onRoutingChanged
    }

    var body: some View {
        AppSheetContainer {
            NavigationStack {
                List {
                    NavigationLink("Remote") {
                        RemoteSessionSettingsView()
                            .navigationTitle("Remote")
                    }
                    NavigationLink("Outputs") {
                        OutputRoutingSettingsForm(
                            sections: .all,
                            onRoutingChanged: onRoutingChanged
                        )
                        .navigationTitle("Outputs")
                    }
                    NavigationLink("Mappings") {
                        InputMappingSettingsView()
                            .navigationTitle("Mappings")
                    }
                    NavigationLink("Help") {
                        HelpSettingsView()
                            .navigationTitle("Help")
                    }
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
#endif
