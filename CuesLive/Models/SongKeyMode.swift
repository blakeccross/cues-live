import Foundation

/// Major or minor quality of a song's key. A missing value reads as major, so songs saved before
/// modes existed keep their labels.
enum SongKeyMode: String, CaseIterable, Codable, Hashable, Sendable {
    case major
    case minor

    init(raw: String?) {
        self = raw.flatMap(SongKeyMode.init(rawValue:)) ?? .major
    }

    var displayName: String {
        switch self {
        case .major: "Major"
        case .minor: "Minor"
        }
    }

    /// Suffix appended to the tonic in compact key labels (`A` + `m`).
    var symbolSuffix: String {
        switch self {
        case .major: ""
        case .minor: "m"
        }
    }

    /// Stored value: nil for major so older files and new major songs serialize the same way.
    var storedRaw: String? {
        self == .major ? nil : rawValue
    }
}
