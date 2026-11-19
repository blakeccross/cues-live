import SwiftUI

/// The trailing "…" button that opens a row's menu.
struct SetlistRowMenuButton<MenuContent: View>: View {
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        SwiftUI.Menu {
            menu()
        } label: {
            Image(systemName: "ellipsis")
                .font(AppTypography.bodyEmphasized)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
        .setlistMenuFittedSizing()
        .appLinkPointer()
        .accessibilityLabel("More actions")
    }
}
