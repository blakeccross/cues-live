import SwiftUI

#if os(macOS)
enum AppSettingsTab: Hashable, CaseIterable, Identifiable {
    case audio
    case timecode
    case groups
    case remote
    case mapping

    var id: Self { self }

    var title: String {
        switch self {
        case .audio: "Audio"
        case .timecode: "Timecode"
        case .groups: "Groups"
        case .remote: "Remote"
        case .mapping: "Mapping"
        }
    }

    var systemImage: String {
        switch self {
        case .audio: "speaker.wave.2"
        case .timecode: "timelapse"
        case .groups: "rectangle.3.group"
        case .remote: "antenna.radiowaves.left.and.right"
        case .mapping: "keyboard"
        }
    }
}

@Observable
final class AppSettingsNavigation {
    static let shared = AppSettingsNavigation()
    var selectedTab: AppSettingsTab = .audio
}
#endif

/// Docs browser used where there is no separate Help window, such as iPhone settings.
struct HelpSettingsView: View {
    var body: some View {
        DocsWindowView()
    }
}
