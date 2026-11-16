import Foundation

/// The samples the click plays: one for the downbeat and one for every other click.
/// `Scripts/generate-click-sounds.py` synthesizes them into the asset catalog.
enum ClickSound: String, CaseIterable, Identifiable, Codable {
    /// Saved as "default"; `default` itself is a Swift keyword.
    case standard = "default"
    case woodblock
    case beep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Default"
        case .woodblock: "Woodblock"
        case .beep: "Beep"
        }
    }

    var accentAssetName: String {
        "Click \(displayName) Accent"
    }

    var normalAssetName: String {
        "Click \(displayName) Normal"
    }
}
