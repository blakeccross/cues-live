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

    /// A stored volume clamped to 0...1; nil means full volume.
    static func volume(_ stored: Double?) -> Double {
        guard let stored, stored.isFinite else { return fullVolume }
        return min(max(stored, 0), fullVolume)
    }
}
