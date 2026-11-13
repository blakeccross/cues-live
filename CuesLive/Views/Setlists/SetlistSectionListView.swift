import SwiftUI

/// The sections of one setlist song, shown when its row is expanded. For the current song each
/// section fills with a progress bar as the playhead crosses it, and passed sections dim. Tapping
/// a section cues it exactly like tapping it in the waveform.
struct SetlistSectionListView: View {
    let sections: [SongSection]
    let playbackIndex: Int
    let isCurrent: Bool
    let isEnabled: Bool
    let playback: SetlistSectionPlayback

    var body: some View {
        if isCurrent {
            // Only the current song's rows redraw with the playhead.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playback.isPlaying)) { _ in
                rows(at: playback.idlePlayheadTime ?? playback.playheadTime())
            }
        } else {
            rows(at: nil)
        }
    }

    private func rows(at time: TimeInterval?) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                SetlistSectionRow(
                    section: section,
                    playheadTime: time,
                    isCued: isCurrent && playback.cuedSectionID == section.id,
                    cueFlashPhase: playback.cueFlashPhase
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isEnabled else { return }
                    playback.selectSection(playbackIndex, section)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Cue") { playback.selectSection(playbackIndex, section) }
                .appLinkPointer()
                .mappableLiveControl(
                    .goToSection(songIndex: playbackIndex, sectionIndex: index),
                    cornerRadius: SetlistSectionRow.cornerRadius
                )
            }
        }
        .padding(.leading, 28 + AppSpacing.sm)
    }
}

private struct SetlistSectionRow: View {
    static let cornerRadius: CGFloat = 8

    let section: SongSection
    /// Nil for songs that aren't current, which show no progress.
    let playheadTime: TimeInterval?
    let isCued: Bool
    let cueFlashPhase: Bool

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
        HStack(spacing: AppSpacing.xs) {
            Text(section.name)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if section.loops {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel("Loops")
            }

            Text(timeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.sm)
        .frame(minHeight: 34)
        .background(progressBackground)
        .overlay(cueOutline)
        .opacity(isPassed ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCued ? "Cued" : "")
    }

    private var progressBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return shape
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
    private var cueOutline: some View {
        if isCued {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(AppColors.accent.opacity(cueFlashPhase ? 1 : 0.35), lineWidth: 2)
        }
    }
}
