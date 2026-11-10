import Foundation

/// Pitch-class root key for a song. Displayed key is this value shifted by `transposeSemitones`.
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

    var semitoneIndex: Int {
        Self.chromaticOrder.firstIndex(of: self) ?? 0
    }

    static func from(semitoneIndex: Int) -> SongMusicalKey {
        let wrapped = ((semitoneIndex % 12) + 12) % 12
        return chromaticOrder[wrapped]
    }

    func transposed(by semitones: Int) -> SongMusicalKey {
        Self.from(semitoneIndex: semitoneIndex + semitones)
    }

    /// Key label for badges, or `nil` when no base key is set.
    static func display(baseRaw: String?, transposeSemitones: Int = 0) -> String? {
        guard let baseRaw, let base = SongMusicalKey(rawValue: baseRaw) else { return nil }
        return base.transposed(by: transposeSemitones).displayName
    }

    /// Transport readout text (`—` when unset).
    static func transportText(baseRaw: String?, transposeSemitones: Int = 0) -> String {
        display(baseRaw: baseRaw, transposeSemitones: transposeSemitones) ?? "—"
    }
}

extension Song {
    var displayedKeyText: String? {
        SongMusicalKey.display(baseRaw: baseKeyRaw, transposeSemitones: transposeSemitones)
    }

    var transportKeyText: String {
        SongMusicalKey.transportText(baseRaw: baseKeyRaw, transposeSemitones: transposeSemitones)
    }
}
