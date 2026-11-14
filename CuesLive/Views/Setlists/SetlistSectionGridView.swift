import SwiftUI

/// The sections of one setlist song as tile cards, shown when its row is expanded. Cards wrap
/// to fit as many across as the width allows. For the current song each card fills with a
/// progress bar as the playhead crosses it, and passed sections dim. Tapping a card cues the
/// section exactly like tapping it in the waveform.
struct SetlistSectionGridView: View {
    let sections: [SongSection]
    let playbackIndex: Int
    let isCurrent: Bool
    let isEnabled: Bool
    let playback: SetlistSectionPlayback

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 220), spacing: AppSpacing.xs, alignment: .top)
    ]

    var body: some View {
        if isCurrent {
            // Only the current song's cards redraw with the playhead.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { _ in
                cards(at: playback.idlePlayheadTime ?? playback.playheadTime())
            }
        } else {
            cards(at: nil)
        }
    }

    private func cards(at time: TimeInterval?) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                SetlistSectionCard(
                    section: section,
                    playheadTime: time,
                    isCued: isCurrent && playback.cuedSectionID == section.id,
                    cueFlashPhase: playback.cueFlashPhase
                )
                .contentShape(RoundedRectangle(cornerRadius: SetlistSectionCard.cornerRadius, style: .continuous))
                .onTapGesture {
                    guard isEnabled else { return }
                    playback.selectSection(playbackIndex, section)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Cue") { playback.selectSection(playbackIndex, section) }
                .appLinkPointer()
                .mappableLiveControl(
                    .goToSection(songIndex: playbackIndex, sectionIndex: index),
                    cornerRadius: SetlistSectionCard.cornerRadius
                )
            }
        }
        .padding(.leading, 28 + AppSpacing.sm)
    }
}

private struct SetlistSectionCard: View {
    static let cornerRadius: CGFloat = 10

    let section: SongSection
    /// Nil for songs that aren't current, which show no progress.
    let playheadTime: TimeInterval?
    let isCued: Bool
    let cueFlashPhase: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    private var progress: Double {
        guard let playheadTime, section.duration > 0 else { return 0 }
        return min(max((playheadTime - section.timelineStartSeconds) / section.duration, 0), 1)
    }

    private var isPassed: Bool {
        guard let playheadTime else { return false }
        return playheadTime >= section.timelineEndSeconds
    }

    private var isActive: Bool {
        guard let playheadTime else { return false }
        return section.containsTimelineTime(playheadTime)
    }

    private var timeText: String {
        guard isActive, let playheadTime else {
            return LiveSetlistDurationFormat.clock(for: section.duration)
        }
        return "-" + LiveSetlistDurationFormat.clock(for: section.timelineEndSeconds - playheadTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(section.name)
                .font(.subheadline.weight(isActive ? .semibold : .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: AppSpacing.xxs) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: 0)
                if section.loops {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityLabel("Loops")
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(progressBackground)
        .overlay(border)
        .opacity(isPassed ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCued ? "Cued" : "")
    }

    private var progressBackground: some View {
        shape
            .fill(AppColors.headerBand)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(AppColors.accent.opacity(0.55))
                        .frame(width: proxy.size.width * progress)
                }
            }
            .clipShape(shape)
    }

    @ViewBuilder
    private var border: some View {
        if isCued {
            shape.strokeBorder(AppColors.accent.opacity(cueFlashPhase ? 1 : 0.35), lineWidth: 2)
        } else {
            shape.strokeBorder(Color.white.opacity(isActive ? 0.14 : 0.06), lineWidth: 1)
        }
    }
}
