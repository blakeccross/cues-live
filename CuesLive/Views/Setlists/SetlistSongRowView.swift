import SwiftUI

/// The header line of a song in the setlist: number or now-playing indicator, title, badges,
/// duration, and the row menu.
struct SetlistSongRowView<MenuContent: View>: View {
    let song: SetlistRowModel.Song
    let isCurrent: Bool
    let isFinished: Bool
    let isPlaying: Bool
    let showsMenu: Bool
    @ViewBuilder let menu: () -> MenuContent

    private var detailText: String? {
        let parts = [song.keyText, song.bpmText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            leadingIndicator
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(isFinished ? AppColors.textTertiary : AppColors.textPrimary)
                    .lineLimit(2)

                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            badges

            Text(song.durationText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isCurrent ? AppColors.textSecondary : AppColors.textTertiary)
                .accessibilityLabel("Duration \(song.durationText)")

            if showsMenu {
                SetlistRowMenuButton(menu: menu)
            }
        }
        .frame(minHeight: AppSpacing.rowMinHeight)
        .opacity(isFinished ? 0.55 : 1)
    }

    @ViewBuilder
    private var badges: some View {
        if song.hasMissingMedia {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .accessibilityLabel("Missing audio files")
                .help("Missing audio files — use Relink Missing Files in the menu")
        }

        if song.hasSmartGuide {
            SmartGuideBadge()
        }

        if let transition = song.transition {
            Image(systemName: transition.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(transition.badgeColor)
                .accessibilityLabel("Transition to next: \(transition.label)")
                .help("Transition to next: \(transition.label)")
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if isCurrent {
            Image(systemName: "speaker.wave.2.fill")
                .font(.subheadline)
                .foregroundStyle(AppColors.accent)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .accessibilityLabel("Now playing")
        } else {
            Text("\(song.playbackIndex + 1)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityHidden(true)
        }
    }
}
