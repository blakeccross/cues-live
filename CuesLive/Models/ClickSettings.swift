import Foundation

/// A song's generated click. It plays from the tempo map at run time and is never a track.
///
/// The accent (the first click of each bar) and the other beats each play their own sample at
/// their own volume. Most songs use one sound's pair, accent and normal, which `sound` reads
/// and writes.
struct ClickSettings: Codable, Hashable {
    static let fullVolume = 1.0

    var isEnabled = false
    var rhythm = ClickRhythm.auto
    var accentSample = ClickSample.accent(of: .standard)
    var beatSample = ClickSample.normal(of: .standard)
    /// Linear gain applied to the accent hit, 0...1.
    var accentVolume = fullVolume
    /// Linear gain applied to every other hit, 0...1.
    var beatVolume = fullVolume

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case rhythm
        /// Files written before separate accent and beat samples have only this key. It is still
        /// written, as the beat sample's sound, so older versions open newer files.
        case sound
        case accentSample
        case beatSample
        case accentVolume
        case beatVolume
    }

    init(isEnabled: Bool = false, rhythm: ClickRhythm = .auto, sound: ClickSound = .standard) {
        self.isEnabled = isEnabled
        self.rhythm = rhythm
        accentSample = .accent(of: sound)
        beatSample = .normal(of: sound)
    }

    /// The sound whose accent and normal samples play, or nil for any other combination.
    /// Setting it restores that sound's pair and leaves the volumes alone.
    var sound: ClickSound? {
        get {
            guard accentSample == .accent(of: beatSample.sound),
                  beatSample == .normal(of: beatSample.sound) else {
                return nil
            }
            return beatSample.sound
        }
        set {
            guard let newValue else { return }
            accentSample = .accent(of: newValue)
            beatSample = .normal(of: newValue)
        }
    }

    /// True when the samples are not one sound's pair, or either plays below full volume.
    var isCustomized: Bool {
        sound == nil || accentVolume != Self.fullVolume || beatVolume != Self.fullVolume
    }

    /// True when `other` plays the same samples at the same levels, so its loaded hits can be reused.
    func hasSameHits(as other: ClickSettings) -> Bool {
        accentSample == other.accentSample && beatSample == other.beatSample
            && accentVolume == other.accentVolume && beatVolume == other.beatVolume
    }

    /// Unknown rhythms or samples from a newer file fall back to the defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        rhythm = (try? container.decodeIfPresent(ClickRhythm.self, forKey: .rhythm)) ?? .auto
        let shared = (try? container.decodeIfPresent(ClickSound.self, forKey: .sound)) ?? .standard
        accentSample = (try? container.decodeIfPresent(ClickSample.self, forKey: .accentSample))
            ?? .accent(of: shared)
        beatSample = (try? container.decodeIfPresent(ClickSample.self, forKey: .beatSample))
            ?? .normal(of: shared)
        accentVolume = Self.volume(try container.decodeIfPresent(Double.self, forKey: .accentVolume))
        beatVolume = Self.volume(try container.decodeIfPresent(Double.self, forKey: .beatVolume))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(rhythm, forKey: .rhythm)
        try container.encode(beatSample.sound, forKey: .sound)
        try container.encode(accentSample, forKey: .accentSample)
        try container.encode(beatSample, forKey: .beatSample)
        try container.encode(accentVolume, forKey: .accentVolume)
        try container.encode(beatVolume, forKey: .beatVolume)
    }

    /// A stored volume clamped to 0...1; missing means full volume.
    static func volume(_ stored: Double?) -> Double {
        guard let stored, stored.isFinite else { return fullVolume }
        return min(max(stored, 0), fullVolume)
    }
}
