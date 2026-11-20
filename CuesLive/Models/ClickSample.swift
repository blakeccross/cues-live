import Foundation

/// One recorded click hit: a sound's accent or normal sample. Either can play on the accent or
/// on the beats. Saved as the sound's raw value, with "-accent" for its accent sample.
struct ClickSample: Hashable, Identifiable, Codable, CaseIterable {
    let sound: ClickSound
    let isAccent: Bool

    private static let accentSuffix = "-accent"

    static let allCases: [ClickSample] = ClickSound.allCases.flatMap { sound in
        [ClickSample(sound: sound, isAccent: false), ClickSample(sound: sound, isAccent: true)]
    }

    static func accent(of sound: ClickSound) -> ClickSample {
        ClickSample(sound: sound, isAccent: true)
    }

    static func normal(of sound: ClickSound) -> ClickSample {
        ClickSample(sound: sound, isAccent: false)
    }

    var id: String { rawValue }

    var rawValue: String {
        isAccent ? sound.rawValue + Self.accentSuffix : sound.rawValue
    }

    init(sound: ClickSound, isAccent: Bool) {
        self.sound = sound
        self.isAccent = isAccent
    }

    init?(rawValue: String) {
        let isAccent = rawValue.hasSuffix(Self.accentSuffix)
        let soundName = isAccent ? String(rawValue.dropLast(Self.accentSuffix.count)) : rawValue
        guard let sound = ClickSound(rawValue: soundName) else { return nil }
        self.init(sound: sound, isAccent: isAccent)
    }

    var displayName: String {
        isAccent ? "\(sound.displayName) (Accent)" : sound.displayName
    }

    var assetName: String {
        isAccent ? sound.accentAssetName : sound.normalAssetName
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        guard let sample = ClickSample(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown click sample \(rawValue)"
            ))
        }
        self = sample
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
