import SwiftUI

/// Marks songs that have Smart Guide section call-outs turned on.
struct SmartGuideBadge: View {
    var body: some View {
        Image(systemName: "person.wave.2.fill")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .accessibilityLabel("Smart Guide on")
            .help("Smart Guide on")
    }
}
