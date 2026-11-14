import SwiftUI

/// Centered toolbar song display: the current song over a small "Up Next" line, set in a
/// continuous rounded panel. Occupies `.principal` so trailing controls stay on the right.
struct LiveToolbarSongTitle: View {
    let title: String
    var upNext: String?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.sm - 2, style: .continuous)
    }

    /// Fills the toolbar's usable height: the macOS unified toolbar leaves 46pt for an item,
    /// while the iOS navigation bar is 44pt overall.
    /// Gap between the title and the "up next" line.
    private static let lineSpacing: CGFloat = 1

    private static var panelHeight: CGFloat {
        #if os(macOS)
        46
        #else
        38
        #endif
    }

    private var hasContent: Bool {
        !title.isEmpty || upNextName != nil
    }

    private var upNextName: String? {
        guard let upNext, !upNext.isEmpty else { return nil }
        return upNext
    }

    var body: some View {
        if hasContent {
            panel
        } else {
            // An empty title (no song loaded) would measure as zero-sized, which AppKit
            // logs as an ambiguous toolbar item.
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private var panel: some View {
        VStack(spacing: Self.lineSpacing) {
            Text(title)
                .font(AppTypography.subheadlineEmphasized)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let upNextName {
                upNextLine(upNextName)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minWidth: 160, minHeight: Self.panelHeight)
        .background(shape.fill(AppColors.headerBand))
        .overlay(shape.strokeBorder(AppColors.cardBorder, lineWidth: 1))
        .contentShape(shape)
    }

    private func upNextLine(_ name: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Text("UP NEXT")
                .font(AppTypography.Compact.label)
                .tracking(0.8)
                .foregroundStyle(AppColors.textTertiary)
            Text(name)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
