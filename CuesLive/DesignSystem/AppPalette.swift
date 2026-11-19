import SwiftUI

/// The fixed set of colors the app draws from. `AppColors` gives them roles; views use those
/// roles, never the palette directly. The app is dark-only, so each color has a single value.
///
/// Before adding a color, reach for the nearest existing step. A new step belongs here only when
/// no existing one works anywhere it is needed.
enum AppPalette {
    // Opaque neutrals, darkest to lightest. As on the usual 50–950 scale, a higher number is darker.
    static let gray950 = Color(.gray950)
    static let gray900 = Color(.gray900)
    static let gray850 = Color(.gray850)
    static let gray800 = Color(.gray800)
    static let gray750 = Color(.gray750)
    static let gray700 = Color(.gray700)
    static let gray600 = Color(.gray600)
    static let gray500 = Color(.gray500)
    static let gray400 = Color(.gray400)
    static let gray300 = Color(.gray300)
    static let gray200 = Color(.gray200)
    static let white = Color.white
    static let black = Color.black

    // Translucent white, for content that should take on whatever it sits over. The first four
    // are background lifts and hairlines; the rest are glyphs and lines over dark or colored fills.
    static let lift1 = Color.white.opacity(0.05)
    static let lift2 = Color.white.opacity(0.08)
    static let lift3 = Color.white.opacity(0.12)
    static let lift4 = Color.white.opacity(0.16)
    static let lift5 = Color.white.opacity(0.55)
    static let lift6 = Color.white.opacity(0.7)
    static let lift7 = Color.white.opacity(0.8)
    static let lift8 = Color.white.opacity(0.9)

    // Translucent black: grid ticks, then shadows and scrims, then text on light fills.
    static let shade1 = Color.black.opacity(0.08)
    static let shade2 = Color.black.opacity(0.12)
    static let shade3 = Color.black.opacity(0.2)
    static let shade4 = Color.black.opacity(0.35)
    static let shade5 = Color.black.opacity(0.5)
    static let shade6 = Color.black.opacity(0.85)

    /// Brand blue, set as the asset catalog's accent color.
    static let accent = Color.accentColor
    static let accentSoft = accent.opacity(0.25)
    static let accentMedium = accent.opacity(0.5)
    static let accentStrong = accent.opacity(0.85)

    // Status and transport hues. System colors, so they match the platform's controls.
    static let red = Color.red
    static let orange = Color.orange
    static let green = Color.green
    static let blue = Color.blue
    static let purple = Color.purple
}
