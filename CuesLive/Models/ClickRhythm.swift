import Foundation

/// How often the click sounds. `auto` follows the time signature's beat unit, so 4/4 clicks
/// quarters and 6/8 clicks eighths; the others are fixed note values.
enum ClickRhythm: String, CaseIterable, Identifiable, Codable {
    case auto
    case half
    case quarter
    case eighth
    case eighthTriplet
    case sixteenth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .half: "1/2"
        case .quarter: "1/4"
        case .eighth: "1/8"
        case .eighthTriplet: "1/8T"
        case .sixteenth: "1/16"
        }
    }

    /// Distance between clicks in a bar whose signature has `denominator` as its beat unit.
    func ticksPerClick(denominator: Int) -> Int {
        let quarter = TempoChange.ticksPerQuarter
        switch self {
        case .auto: return quarter * 4 / max(1, denominator)
        case .half: return quarter * 2
        case .quarter: return quarter
        case .eighth: return quarter / 2
        case .eighthTriplet: return quarter / 3
        case .sixteenth: return quarter / 4
        }
    }
}
