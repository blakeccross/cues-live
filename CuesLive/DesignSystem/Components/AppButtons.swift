import SwiftUI

struct AppPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .frame(minHeight: 44)
                .background(AppColors.accent.opacity(isEnabled ? 1 : 0.4), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .appPressable(isEnabled: isEnabled)
    }
}

struct AppSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(minHeight: 44)
            .background(AppColors.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .appPressable(isEnabled: isEnabled)
    }
}

struct AppIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    var isActive: Bool = false
    var isEnabled: Bool = true
    /// Glyph color while active. `nil` brightens the glyph to the primary text color.
    var tint: Color? = nil
    var iconColor: Color? = nil
    /// Glyph point size as a fraction of `size`.
    var iconScale: CGFloat = 0.38
    var flipsImageHorizontally: Bool = false
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(AppIconButtonStyle(
            size: size,
            isOn: isActive,
            tint: tint,
            iconColor: iconColor,
            iconScale: iconScale,
            flipsImageHorizontally: flipsImageHorizontally
        ))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}
