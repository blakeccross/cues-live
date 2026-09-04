import SwiftUI

#if os(macOS)
enum AppSettingsTab: Hashable {
    case audio
    case timecode
    case groups
    case remote
    case mapping
    case general
    case help
}

@Observable
final class AppSettingsNavigation {
    static let shared = AppSettingsNavigation()
    var selectedTab: AppSettingsTab = .audio
}
#endif

/// Embedded docs browser for Settings and iOS sheets.
struct HelpSettingsView: View {
    var body: some View {
        DocsWindowView()
    }
}
