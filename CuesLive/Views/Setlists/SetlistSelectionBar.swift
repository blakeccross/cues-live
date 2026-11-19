import SwiftUI

#if os(iOS)
/// Bulk actions for the rows selected while the setlist is in Edit mode.
struct SetlistSelectionBar: View {
    let count: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(count == 1 ? "1 item selected" : "\(count) items selected")
                .font(AppTypography.subheadlineEmphasized.monospacedDigit())
                .foregroundStyle(count == 0 ? AppColors.textTertiary : AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: AppSpacing.xs)

            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
            .disabled(count == 0)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 0.5)
        }
    }
}
#endif
