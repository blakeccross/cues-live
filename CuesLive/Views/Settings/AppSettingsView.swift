#if os(macOS)
import Sparkle
import SwiftUI

/// Native macOS Settings window (cues.live → Settings… / ⌘,).
struct AppSettingsView: View {
    let updater: SPUUpdater
    @Bindable private var navigation = AppSettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            audioPane
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                .tag(AppSettingsTab.audio)

            timecodePane
                .tabItem {
                    Label("Timecode", systemImage: "timelapse")
                }
                .tag(AppSettingsTab.timecode)

            groupsPane
                .tabItem {
                    Label("Groups", systemImage: "rectangle.3.group")
                }
                .tag(AppSettingsTab.groups)

            remoteSessionPane
                .tabItem {
                    Label("Remote", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(AppSettingsTab.remote)

            mappingPane
                .tabItem {
                    Label("Mapping", systemImage: "keyboard")
                }
                .tag(AppSettingsTab.mapping)

            GeneralSettingsPane(updater: updater)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(AppSettingsTab.general)

            helpPane
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .tag(AppSettingsTab.help)
        }
        .frame(width: 560, height: 560)
        .preferredColorScheme(.dark)
    }

    private var audioPane: some View {
        SettingsPaneScroll {
            OutputRoutingSettingsForm(sections: .audio)
        }
    }

    private var timecodePane: some View {
        SettingsPaneScroll {
            OutputRoutingSettingsForm(sections: .timecodeOnly)
        }
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

    private var helpPane: some View {
        HelpSettingsView()
    }
}

private struct SettingsPaneScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(AppSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.backgroundSecondary)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        SettingsPaneScroll {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    AppSectionHeader(title: "Updates")

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("cues.live can check for new versions automatically.")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Check for Updates…") {
                            updater.checkForUpdates()
                        }
                        .disabled(!viewModel.canCheckForUpdates)
                        .buttonStyle(.bordered)
                    }
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    AppSectionHeader(title: "Appearance")

                    Text("The live performance UI always uses dark appearance for stage readability.")
                        .font(.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(AppSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
            }
        }
    }
}
#endif
