import SwiftUI

/// Bulk actions for the songs selected in the library.
struct SongLibrarySelectionBar: View {
    let count: Int
    let onAddToSetlist: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Text(count == 1 ? "1 song selected" : "\(count) songs selected")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(count == 0 ? AppColors.textTertiary : AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: AppSpacing.xs)

            Button(action: onAddToSetlist) {
                Label("Add to Setlist", systemImage: "text.badge.plus")
            }
            .help("Add selected songs to the setlist")

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete selected songs")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(count == 0)
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
