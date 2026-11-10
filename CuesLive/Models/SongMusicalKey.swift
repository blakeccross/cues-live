import Foundation

/// Pitch-class root key for a song.
enum SongMusicalKey: String, CaseIterable, Codable, Hashable, Sendable {
    case c = "C"
    case cSharp = "C#"
    case d = "D"
    case eFlat = "Eb"
    case e = "E"
    case f = "F"
    case fSharp = "F#"
    case g = "G"
    case aFlat = "Ab"
    case a = "A"
    case bFlat = "Bb"
    case b = "B"

    /// Chromatic order from C through B.
    static let chromaticOrder: [SongMusicalKey] = [
        .c, .cSharp, .d, .eFlat, .e, .f, .fSharp, .g, .aFlat, .a, .bFlat, .b
    ]

    var displayName: String { rawValue }

    /// Key label for badges, or `nil` when no key is set.
    static func display(baseRaw: String?) -> String? {
        guard let baseRaw, let base = SongMusicalKey(rawValue: baseRaw) else { return nil }
        return base.displayName
    }

    /// Transport readout text (`—` when unset).
    static func transportText(baseRaw: String?) -> String {
        display(baseRaw: baseRaw) ?? "—"
    }
}

extension Song {
    var displayedKeyText: String? {
        SongMusicalKey.display(baseRaw: baseKeyRaw)
    }

    var transportKeyText: String {
        SongMusicalKey.transportText(baseRaw: baseKeyRaw)
    }
}
