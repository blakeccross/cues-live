import SwiftUI

extension Color {
    static var dawTimelineBackground: Color {
        AppColors.backgroundPrimary
    }

    /// Fully opaque background for pinned ruler headers so scrolling tracks don't show through.
    static var dawStickyRulerBackground: Color {
        AppColors.surfaceElevated
    }

    static var dawTrackHeaderBackground: Color {
        AppColors.backgroundSecondary
    }

    static var dawTrackHeaderColumnBackground: Color {
        AppColors.backgroundPrimary
    }

    static var dawTimelineDivider: Color {
        AppColors.separator
    }

    static var dawMixButtonBackground: Color {
        AppColors.surface
    }

    static var dawSoloActive: Color {
        AppColors.soloActive
    }

    static var dawMuteActive: Color {
        AppColors.muteActive
    }

    static var dawMeasureGridLine: Color {
        AppColors.separator.opacity(0.6)
    }

    static var dawWaveformFill: Color {
        AppColors.textSecondary.opacity(0.6)
    }

    /// Voice Memos–style live waveform colors.
    static var liveVoiceMemosPlayed: Color {
        Color(red: 1.0, green: 0.584, blue: 0.0)
    }

    static var liveVoiceMemosUnplayed: Color {
        Color(white: 0.42)
    }

    static var liveVoiceMemosBackground: Color {
        Color(white: 0.06)
    }

    static var dawTrackHeaderSelected: Color {
        AppColors.trackHeaderSelected
    }

    static var dawPlayheadFill: Color {
        Color(white: 0.82)
    }

    static var dawPlayheadBorder: Color {
        Color(white: 0.12)
    }
}

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
            case .red: return Color("TrackPaletteRed")
            case .orange: return Color("TrackPaletteOrange")
            case .amber: return Color("TrackPaletteAmber")
            case .gold: return Color("TrackPaletteGold")
            case .yellow: return Color("TrackPaletteYellow")
            case .green: return Color("TrackPaletteGreen")
            case .teal: return Color("TrackPaletteTeal")
            case .cyan: return Color("TrackPaletteCyan")
            case .sky: return Color("TrackPaletteSky")
            case .blue: return Color("TrackPaletteBlue")
            case .indigo: return Color("TrackPaletteIndigo")
            case .violet: return Color("TrackPaletteViolet")
            case .purple: return Color("TrackPalettePurple")
            case .magenta: return Color("TrackPaletteMagenta")
            case .pink: return Color("TrackPalettePink")
            case .brown: return Color("TrackPaletteBrown")
            case .gray: return Color("TrackPaletteGray")
            case .darkGray: return Color("TrackPaletteDarkGray")
            case .white: return Color("TrackPaletteWhite")
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
