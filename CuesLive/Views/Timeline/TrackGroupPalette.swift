import SwiftUI

/// Track and group colors chosen from the palette, and the header/body pair derived from each.
enum TrackGroupPalette {
    enum Key: String, CaseIterable, Identifiable {
        case red
        case orange
        case amber
        case gold
        case yellow
        case green
        case teal
        case cyan
        case sky
        case blue
        case indigo
        case violet
        case purple
        case magenta
        case pink
        case brown
        case gray
        case darkGray
        case white

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .darkGray: return "Dark Gray"
            default: return rawValue.capitalized
            }
        }

        var color: Color {
            switch self {
            case .red: return Color(.trackPaletteRed)
            case .orange: return Color(.trackPaletteOrange)
            case .amber: return Color(.trackPaletteAmber)
            case .gold: return Color(.trackPaletteGold)
            case .yellow: return Color(.trackPaletteYellow)
            case .green: return Color(.trackPaletteGreen)
            case .teal: return Color(.trackPaletteTeal)
            case .cyan: return Color(.trackPaletteCyan)
            case .sky: return Color(.trackPaletteSky)
            case .blue: return Color(.trackPaletteBlue)
            case .indigo: return Color(.trackPaletteIndigo)
            case .violet: return Color(.trackPaletteViolet)
            case .purple: return Color(.trackPalettePurple)
            case .magenta: return Color(.trackPaletteMagenta)
            case .pink: return Color(.trackPalettePink)
            case .brown: return Color(.trackPaletteBrown)
            case .gray: return Color(.trackPaletteGray)
            case .darkGray: return Color(.trackPaletteDarkGray)
            case .white: return Color(.trackPaletteWhite)
            }
        }
    }

    private static let headerDarkenFactor = 0.72
    private static let selectedHeaderLightenAmount = 0.45

    /// Header (and side/bottom border) color of a selected clip: the track color lightened, so a
    /// selected clip reads as brighter than its neighbors whatever its palette.
    static func selectedHeaderColor(forPaletteKey key: String?) -> Color {
        bodyColor(forPaletteKey: key).lightened(sRGBToward: selectedHeaderLightenAmount)
    }

    static func colors(for group: TrackGroup?) -> (header: Color, body: Color) {
        colors(forPaletteKey: group?.paletteKey)
    }

    static func colors(forGroupName name: String?) -> (header: Color, body: Color) {
        colors(forPaletteKey: defaultKey(forGroupName: name)?.rawValue)
    }

    static func colors(forPaletteKey key: String?) -> (header: Color, body: Color) {
        let body = bodyColor(forPaletteKey: key)
        return (body.darkened(sRGBBy: headerDarkenFactor), body)
    }

    static func defaultKey(forGroupName name: String?) -> Key? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        switch trimmed.lowercased() {
        case "drums":
            return .red
        case "percussion":
            return .orange
        case "bass", "eg", "ag":
            return .blue
        case "keys", "synth":
            return .green
        case "lv", "bgv":
            return .purple
        case "strings":
            return .brown
        case "click":
            return .darkGray
        case "cues":
            return .white
        case "other":
            return .gray
        default:
            return .gray
        }
    }

    private static func bodyColor(forPaletteKey key: String?) -> Color {
        guard let raw = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let matched = Key(rawValue: raw) else {
            return Key.gray.color
        }
        return matched.color
    }
}
