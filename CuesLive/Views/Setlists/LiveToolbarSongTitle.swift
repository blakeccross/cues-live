import SwiftUI

/// Centered macOS toolbar title. Occupies `.principal` so trailing controls stay on the right.
struct LiveToolbarSongTitle: View {
    let title: String
    var upNext: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let upNext, !upNext.isEmpty {
                Text("Up Next: \"\(upNext)\"")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        // An empty title (no song loaded) would measure as zero-sized, which AppKit
        // logs as an ambiguous toolbar item.
        .frame(minWidth: 1, minHeight: 1)
    }
}
