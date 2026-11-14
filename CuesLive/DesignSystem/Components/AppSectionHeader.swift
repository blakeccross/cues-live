import SwiftUI

struct AppSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.title)
            .foregroundStyle(AppColors.textPrimary)
    }
}
