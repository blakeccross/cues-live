import Foundation

/// A song's generated click. It plays from the tempo map at run time and is never a track.
struct ClickSettings: Codable, Hashable {
    var isEnabled = false
    var rhythm = ClickRhythm.auto
    var sound = ClickSound.standard

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case rhythm
        case sound
    }

    init(isEnabled: Bool = false, rhythm: ClickRhythm = .auto, sound: ClickSound = .standard) {
        self.isEnabled = isEnabled
        self.rhythm = rhythm
        self.sound = sound
    }

    /// Unknown rhythms or sounds from a newer file fall back to the defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        rhythm = (try? container.decodeIfPresent(ClickRhythm.self, forKey: .rhythm)) ?? .auto
        sound = (try? container.decodeIfPresent(ClickSound.self, forKey: .sound)) ?? .standard
    }
}
