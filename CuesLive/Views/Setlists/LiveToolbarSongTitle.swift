import SwiftUI

/// Centered toolbar song display: the current song over a small "Up Next" line or a row of
/// labelled details, set in a continuous rounded panel. Occupies `.principal` so trailing
/// controls stay on the right.
struct LiveToolbarSongTitle: View {
    /// One column under the title: a small label over a value set at the title's size.
    struct Detail: Identifiable {
        let label: String
        let value: String

        var id: String { label }
    }

    let title: String
    var upNext: String?
    var details: [Detail] = []

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.sm - 2, style: .continuous)
    }

    /// Fills the toolbar's usable height: the macOS unified toolbar leaves 46pt for an item,
    /// while the iOS navigation bar is 44pt overall.
    /// Gap between the title and the "up next" line.
    private static let lineSpacing: CGFloat = 1
    /// Gap between a detail's label and its value.
    private static let detailLabelSpacing: CGFloat = 0

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
            if !details.isEmpty {
                detailRow
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minWidth: 160, minHeight: Self.panelHeight)
        .background(shape.fill(AppColors.headerBand))
        .overlay(shape.strokeBorder(AppColors.cardBorder, lineWidth: 1))
        .contentShape(shape)
    }

    private var detailRow: some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(details) { detail in
                VStack(spacing: Self.detailLabelSpacing) {
                    Text(detail.label.uppercased())
                        .font(AppTypography.Compact.microLabel)
                        .tracking(0.6)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(detail.value)
                        .font(AppTypography.subheadlineEmphasized.monospacedDigit())
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
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
