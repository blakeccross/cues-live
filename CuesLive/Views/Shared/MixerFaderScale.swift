import Foundation

enum MixerFaderScale {
    /// Top of the group fader. Unity (0 dB) sits one step below this.
    static let maxBoostDB: Double = 6
    static let maxAttenuationDB: Double = 60
    static let markerStepDB: Double = 6
    /// Matches the fader cap so scale marks line up with the thumb center.
    static let thumbHeight: CGFloat = 40
    /// Gap between a fader and its level meter.
    static let meterGap: CGFloat = 3
    /// Gap between the grip lines on the fader thumb.
    static let gripLineSpacing: CGFloat = 3
    static let meterCornerRadius: CGFloat = 2

    static var spanDB: Double { maxBoostDB + maxAttenuationDB }

    /// +6, 0, −6, −12 … −60.
    static var markerDecibels: [Int] {
        Array(stride(from: Int(maxBoostDB), through: -Int(maxAttenuationDB), by: -Int(markerStepDB)))
    }

    static func decibels(forLinearGain gain: Double) -> Double {
        guard gain > 0.000_001 else { return -maxAttenuationDB }
        let db = 20 * log10(gain)
        return min(maxBoostDB, max(-maxAttenuationDB, db))
    }

    static func linearGain(forDecibels db: Double) -> Double {
        let clamped = min(maxBoostDB, max(-maxAttenuationDB, db))
        return pow(10, clamped / 20)
    }

    static func normalizedPosition(forDecibels db: Double) -> Double {
        let clamped = min(maxBoostDB, max(-maxAttenuationDB, db))
        return (maxBoostDB - clamped) / spanDB
    }

    static func normalizedPosition(forLinearGain gain: Double) -> Double {
        normalizedPosition(forDecibels: decibels(forLinearGain: gain))
    }

    static func linearGain(forNormalizedPosition position: Double) -> Double {
        let clamped = min(1, max(0, position))
        let db = maxBoostDB - clamped * spanDB
        return linearGain(forDecibels: db)
    }

    /// Group fader meters, on the same +6…−60 scale as the numbered marks.
    static func faderMeterFillFraction(forPeak peak: Float) -> CGFloat {
        guard peak > 0.000_001 else { return 0 }
        let db = min(maxBoostDB, max(-maxAttenuationDB, 20 * log10(Double(peak))))
        return CGFloat((db + maxAttenuationDB) / spanDB)
    }

    static func markerLabel(for db: Int) -> String {
        if db > 0 { return "+\(db)" }
        if db == 0 { return "0" }
        return "−\(abs(db))"
    }
}
