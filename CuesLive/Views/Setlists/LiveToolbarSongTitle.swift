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
        VStack(spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
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
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .contentShape(shape)
    }

    private func upNextLine(_ name: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Text("UP NEXT")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(AppColors.textTertiary)
            Text(name)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
