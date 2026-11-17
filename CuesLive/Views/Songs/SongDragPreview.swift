#if os(macOS)
import SwiftUI

/// The image under the pointer while songs are dragged out of the library: the grabbed song's
/// name on a card, stacked with a count badge when the drag carries a multi-selection, as Finder does.
struct SongDragPreview: View {
    static let stackOffset: CGFloat = 4
    static let maximumTitleWidth: CGFloat = 220

    let title: String
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if count > 1 {
                    card(content: label.hidden())
                        .offset(x: Self.stackOffset, y: Self.stackOffset)
                }
                card(content: label)
            }
            .padding(Self.stackOffset)

            if count > 1 {
                Text("\(count)")
                    .font(AppTypography.caption2Emphasized.monospacedDigit())
                    .foregroundStyle(AppColors.textOnFill)
                    .padding(AppSpacing.chipInsets)
                    .background(AppColors.accent, in: Capsule())
            }
        }
        .accessibilityLabel(count > 1 ? "\(count) songs" : title)
    }

    private var label: some View {
        Label(title, systemImage: "music.note")
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: Self.maximumTitleWidth, alignment: .leading)
    }

    private func card<Content: View>(content: Content) -> some View {
        content
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppRadius.xs))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.xs).stroke(AppColors.cardBorder))
    }
}
#endif
