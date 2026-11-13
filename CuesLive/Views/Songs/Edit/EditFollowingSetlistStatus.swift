import SwiftUI

/// Bottom bar for an editor that follows setlist playback, shown in place of the transport.
struct EditFollowingSetlistStatus: View {
    /// False when the window was sent a song the setlist is not on.
    let isActiveSong: Bool

    var body: some View {
        if isActiveSong {
            statusLabel(
                "Following the setlist. Edits apply live; control playback from the setlist window.",
                systemImage: "link"
            )
        } else {
            HStack(spacing: AppSpacing.sm) {
                statusLabel(
                    "Not the playing song. Edits are saved and play when the setlist reaches it.",
                    systemImage: "pin"
                )
                Button("Follow Setlist") {
                    SetlistEditorLink.shared.followSetlist()
                }
                .controlSize(.small)
            }
        }
    }

    private func statusLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(AppTypography.caption())
            .foregroundStyle(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.vertical, AppSpacing.xxs)
    }
}
