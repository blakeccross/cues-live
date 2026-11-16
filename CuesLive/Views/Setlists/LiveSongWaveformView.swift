import SwiftUI

/// A setlist song lane's SwiftUI layer: its size, section labels, and the taps, context menus
/// and mapping targets on it. The lane's background, sections, grid and waveform are drawn
/// behind it by `LiveSetlistLanePainter`, which reads this view's frame from the scroll model.
struct LiveSongWaveformView: View {
    let contentWidth: CGFloat
    /// The in-to-out stretch the lane shows.
    let window: LiveLaneWindow
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

    private var usesArrangementLayout: Bool {
        !sections.isEmpty
    }

    var body: some View {
        Color.clear
            .frame(width: contentWidth, height: waveformHeight)
            .overlay(alignment: .topLeading) {
                sectionMarkers
                    .frame(width: contentWidth, height: waveformHeight, alignment: .topLeading)
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
                window: window,
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
            ZStack(alignment: .topLeading) {
                ForEach(sections) { section in
                    let startX = window.x(for: section.timelineStartSeconds, width: contentWidth)
                    let endX = window.x(for: section.timelineEndSeconds, width: contentWidth)
                    let segmentWidth = max(0, endX - startX)

                    sectionLabel(section, width: segmentWidth)
                        .offset(x: startX)

                    if showsMissingMediaWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(AppTypography.Compact.overlayGlyph)
                            .foregroundStyle(AppColors.warning)
                            .frame(width: segmentWidth, height: waveformHeight - ribbonHeight)
                            .offset(x: startX, y: ribbonHeight)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var ribbonHeight: CGFloat {
        LiveSetlistWaveformMetrics.sectionRibbonHeight
    }

    /// The section's name inside its marker in the ribbon the lane painter draws.
    private func sectionLabel(_ section: SongSection, width: CGFloat) -> some View {
        HStack(spacing: AppSpacing.tagGlyphGap) {
            if loopSectionIDs.contains(section.id) {
                Image(systemName: "repeat")
                    .font(AppTypography.Compact.glyphEmphasized)
            }
            Text(section.name)
                .font(AppTypography.Compact.sectionName)
                .lineLimit(1)
        }
        .foregroundStyle(AppColors.LiveWaveform.sectionLabel)
        .padding(.horizontal, AppSpacing.xs)
        .frame(width: width, height: ribbonHeight, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func sectionMappingTargets(playbackIndex: Int, contentWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                let startX = window.x(for: section.timelineStartSeconds, width: contentWidth)
                let endX = window.x(for: section.timelineEndSeconds, width: contentWidth)
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
                    let startX = window.x(for: section.timelineStartSeconds, width: contentWidth)
                    let endX = window.x(for: section.timelineEndSeconds, width: contentWidth)
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
