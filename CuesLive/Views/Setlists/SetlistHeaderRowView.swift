import SwiftUI

/// A section header row in the setlist: title, optional clock, and the row menu.
struct SetlistHeaderRowView<MenuContent: View>: View {
    let title: String
    let timeText: String?
    let showsMenu: Bool
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.captionEmphasized)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let timeText {
                Text(timeText)
                    .font(AppTypography.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityLabel("Time \(timeText)")
            }

            if showsMenu {
                SetlistRowMenuButton(menu: menu)
            }
        }
        .frame(minHeight: 40)
    }
}
