import SwiftUI

/// A setlist song lane's SwiftUI layer: its size, section labels, and the taps, context menus
/// and mapping targets on it. The lane's background, sections, grid and waveform are drawn
/// behind it by `LiveSetlistLanePainter`, which reads this view's frame from the scroll model.
struct LiveSongWaveformView: View {
    let contentWidth: CGFloat
    let timelineDuration: TimeInterval
    let sections: [SongSection]
    let loopSectionIDs: Set<UUID>
    var isInteractive = true
    /// Shows a caution icon in every section when the song has missing audio files.
    var showsMissingMediaWarning = false
    let onSeek: (TimeInterval) -> Void
    let onCueSection: (SongSection) -> Void
    /// Setlist position of this lane. When set, each section can be key- or MIDI-mapped.
    var playbackIndex: Int? = nil

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight
    @Environment(InputMappingController.self) private var mapping

    private var safeTimelineDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    private var usesArrangementLayout: Bool {
        !sections.isEmpty
    }

    var body: some View {
        Color.clear
            .frame(width: contentWidth, height: waveformHeight)
            .overlay(alignment: .topLeading) {
                sectionMarkers
                    .frame(width: contentWidth, height: waveformHeight, alignment: .leading)
            }
            .overlay(alignment: .topLeading) {
                if isInteractive {
                    sectionTapTargets(contentWidth: contentWidth)
                }
            }
            .overlay(alignment: .topLeading) {
                if let playbackIndex, mapping.showsLiveHighlights {
                    sectionMappingTargets(playbackIndex: playbackIndex, contentWidth: contentWidth)
                }
            }
            .modifier(WaveformSeekGestureModifier(
                isEnabled: isInteractive && !mapping.showsLiveHighlights,
                contentWidth: contentWidth,
                duration: safeTimelineDuration,
                sections: sections.map {
                    WaveformSeekGestureModifier.SectionHitTarget(
                        id: $0.id,
                        start: $0.timelineStartSeconds,
                        end: $0.timelineEndSeconds
                    )
                },
                onSectionTap: { sectionID in
                    guard let section = sections.first(where: { $0.id == sectionID }) else { return }
                    onCueSection(section)
                },
                onSeek: onSeek
            ))
    }

    @ViewBuilder
    private var sectionMarkers: some View {
        if usesArrangementLayout {
            ZStack(alignment: .leading) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    let startX = TimelineLayout.xPosition(
                        for: section.timelineStartSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let endX = TimelineLayout.xPosition(
                        for: section.timelineEndSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let segmentWidth = max(0, endX - startX)
                    let palette = ArrangementSectionPalette.colors(for: index)
                    let isLoopSection = loopSectionIDs.contains(section.id)

                    HStack(spacing: 3) {
                        if isLoopSection {
                            Image(systemName: "repeat")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(palette.accent)
                        }
                        Text(section.name.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColors.surfaceElevated.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    .padding(.leading, 4)
                    .padding(.top, 4)
                    .frame(width: segmentWidth, height: waveformHeight, alignment: .topLeading)
                    .offset(x: startX)

                    if showsMissingMediaWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.orange)
                            .frame(width: segmentWidth, height: waveformHeight)
                            .offset(x: startX)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func sectionMappingTargets(playbackIndex: Int, contentWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                let startX = TimelineLayout.xPosition(
                    for: section.timelineStartSeconds,
                    duration: safeTimelineDuration,
                    contentWidth: contentWidth
                )
                let endX = TimelineLayout.xPosition(
                    for: section.timelineEndSeconds,
                    duration: safeTimelineDuration,
                    contentWidth: contentWidth
                )
                let segmentWidth = max(0, endX - startX)

                Color.clear
                    .frame(width: segmentWidth, height: waveformHeight)
                    .mappableLiveControl(
                        .goToSection(songIndex: playbackIndex, sectionIndex: index),
                        cornerRadius: AppRadius.sm
                    )
                    .offset(x: startX)
            }
        }
        .frame(width: contentWidth, height: waveformHeight, alignment: .leading)
    }

    @ViewBuilder
    private func sectionTapTargets(contentWidth: CGFloat) -> some View {
        if usesArrangementLayout {
            ZStack(alignment: .leading) {
                ForEach(sections) { section in
                    let startX = TimelineLayout.xPosition(
                        for: section.timelineStartSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let endX = TimelineLayout.xPosition(
                        for: section.timelineEndSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let segmentWidth = max(0, endX - startX)

                    Color.clear
                        .frame(width: segmentWidth, height: waveformHeight)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Cue Section") {
                                onCueSection(section)
                            }
                        }
                        .offset(x: startX)
                }
            }
        }
    }
}

struct SetlistWaveformHeaderMarker: View {
    let title: String
    /// Matches the MIDI-lane space reserved below song waveforms, so the
    /// divider spans the same height as the surrounding song lanes.
    var extraHeight: CGFloat = 0

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    private let markerWidth: CGFloat = 40

    var body: some View {
        let totalHeight = waveformHeight + extraHeight
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColors.backgroundPrimary)
            .overlay {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    // Lay out along the vertical axis before rotating into the marker.
                    .frame(width: max(0, totalHeight - AppSpacing.md), height: markerWidth)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: markerWidth, height: totalHeight)
            .clipped()
    }
}
