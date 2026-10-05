import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum AppColors {
    static let backgroundPrimary = Color("BackgroundPrimary")
    static let backgroundSecondary = Color("BackgroundSecondary")
    static let surface = Color("Surface")
    static let surfaceElevated = Color("SurfaceElevated")

    static let textPrimary = Color.white
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")

    /// Brand orange (#E25303) — reserved for current/active state.
    static let accent = Color.accentColor
    static let separator = Color("Separator")

    static let soloActive = Color("SoloActive")
    static let muteActive = Color("MuteActive")

    /// Highlighted track header background when the track row is selected.
    static let trackHeaderSelected = Color("TrackHeaderSelected")
}

extension Color {
    func darkened(sRGBBy factor: Double) -> Color {
        #if canImport(AppKit)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            .sRGB,
            red: clamped(Double(color.redComponent) * factor),
            green: clamped(Double(color.greenComponent) * factor),
            blue: clamped(Double(color.blueComponent) * factor),
            opacity: Double(color.alphaComponent)
        )
        #elseif canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
        return Color(
            .sRGB,
            red: clamped(Double(red) * factor),
            green: clamped(Double(green) * factor),
            blue: clamped(Double(blue) * factor),
            opacity: Double(alpha)
        )
        #else
        return self
        #endif
    }

    /// Mixes the color toward white by `amount` (0 = unchanged, 1 = white), keeping its hue.
    func lightened(sRGBToward amount: Double) -> Color {
        func mix(_ component: Double) -> Double {
            clamped(component + (1 - component) * amount)
        }

        #if canImport(AppKit)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            .sRGB,
            red: mix(Double(color.redComponent)),
            green: mix(Double(color.greenComponent)),
            blue: mix(Double(color.blueComponent)),
            opacity: Double(color.alphaComponent)
        )
        #elseif canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
        return Color(
            .sRGB,
            red: mix(Double(red)),
            green: mix(Double(green)),
            blue: mix(Double(blue)),
            opacity: Double(alpha)
        )
        #else
        return self
        #endif
    }

    private func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
