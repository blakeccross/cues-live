import SwiftUI

/// Bare icon look shared by `AppIconButton` and `AppIconToggle`. While `isOn`, the glyph
/// takes `tint`, the way Music colors its shuffle and repeat buttons. Works as a button
/// style and, through `.toggleStyle(.button)`, for toggles.
struct AppIconButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var isOn: Bool = false
    /// Glyph color while on. `nil` brightens the glyph to the primary text color.
    var tint: Color? = nil
    var iconColor: Color? = nil
    /// Glyph point size as a fraction of `size`.
    var iconScale: CGFloat = 0.38
    var flipsImageHorizontally: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        AppIconButtonStyleBody(style: self, label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct AppIconButtonStyleBody<Label: View>: View {
    let style: AppIconButtonStyle
    let label: Label
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled

    private var glyphColor: Color {
        if style.isOn {
            return style.tint ?? AppColors.textPrimary
        }
        return style.iconColor ?? AppColors.iconNeutral
    }

    var body: some View {
        label
            .labelStyle(.iconOnly)
            .font(.system(size: style.size * style.iconScale, weight: .semibold))
            .foregroundStyle(glyphColor)
            .scaleEffect(x: style.flipsImageHorizontally ? -1 : 1, y: 1)
            .frame(width: style.size, height: style.size)
            .contentShape(Rectangle())
            .animation(AppAnimation.fadeQuick, value: style.isOn)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(isPressed && isEnabled ? 0.97 : 1)
            .animation(AppAnimation.springSnappy, value: isPressed)
    }
}
