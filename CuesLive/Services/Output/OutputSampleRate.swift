import Foundation

/// The rate cues.live mixes at and asks the output device to run at.
///
/// Stored per machine, like the other app preferences, not in songs: the right rate
/// depends on the interface and the rest of the rig, not on the material.
enum OutputSampleRate {
    static let choices: [Double] = [44_100, 48_000, 88_200, 96_000]
    /// Also the rate the generated click, timecode and spoken guide are rendered at; the
    /// mixer resamples them, like any stem at another rate, when a different rate is selected.
    static let defaultRate = DecodedStemBuffer.engineSampleRate
    static let storageKey = "outputSampleRate"

    /// The user's choice, or the default when nothing valid is stored.
    static func selected(in defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: storageKey)
        return choices.contains(stored) ? stored : defaultRate
    }

    /// Stores `rate`; rates outside `choices` are ignored.
    static func select(_ rate: Double, in defaults: UserDefaults = .standard) {
        guard choices.contains(rate) else { return }
        defaults.set(rate, forKey: storageKey)
    }

    /// "44.1 kHz", "48 kHz".
    static func label(for rate: Double) -> String {
        let kilohertz = rate / 1000
        let digits = kilohertz.rounded() == kilohertz ? 0 : 1
        return String(format: "%.\(digits)f kHz", kilohertz)
    }
}
