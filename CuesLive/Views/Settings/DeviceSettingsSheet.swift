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
                RemoteSessionSettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink("Outputs") {
                                ScrollView {
                                    OutputRoutingSettingsForm(
                                        sections: .all,
                                        onRoutingChanged: onRoutingChanged
                                    )
                                    .padding(AppSpacing.lg)
                                }
                                .navigationTitle("Manage Outputs")
                            }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink("Mappings") {
                                InputMappingSettingsView()
                                    .navigationTitle("Mappings")
                            }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink("Help") {
                                HelpSettingsView()
                                    .navigationTitle("Help")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                                .foregroundStyle(AppColors.accent)
                        }
                    }
            }
        }
        .presentationDetents([.large])
    }
}
#endif
