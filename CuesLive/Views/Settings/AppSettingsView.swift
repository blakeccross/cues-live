#if os(macOS)
import SwiftUI

/// Native macOS Settings window (cues.live → Settings… / ⌘,).
struct AppSettingsView: View {
    @Bindable private var navigation = AppSettingsNavigation.shared

    var body: some View {
        settingsTabs
            .frame(width: 560, height: 560)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var settingsTabs: some View {
        if #available(macOS 15.0, *) {
            TabView(selection: $navigation.selectedTab) {
                ForEach(AppSettingsTab.allCases) { tab in
                    Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                        pane(for: tab)
                    }
                }
            }
        } else {
            TabView(selection: $navigation.selectedTab) {
                ForEach(AppSettingsTab.allCases) { tab in
                    pane(for: tab)
                        .tag(tab)
                        .tabItem {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func pane(for tab: AppSettingsTab) -> some View {
        switch tab {
        case .audio:
            audioPane
        case .timecode:
            timecodePane
        case .groups:
            groupsPane
        case .remote:
            remoteSessionPane
        case .mapping:
            mappingPane
        }
    }

    private var audioPane: some View {
        OutputRoutingSettingsForm(sections: .audio)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timecodePane: some View {
        OutputRoutingSettingsForm(sections: .timecodeOnly)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupsPane: some View {
        TrackGroupEditorView(presentation: .settings)
    }

    private var remoteSessionPane: some View {
        RemoteSessionSettingsView()
    }

    private var mappingPane: some View {
        InputMappingSettingsView()
    }
}
#endif
