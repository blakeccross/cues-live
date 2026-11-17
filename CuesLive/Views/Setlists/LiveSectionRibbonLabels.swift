import SwiftUI

/// Section names, and loop and missing-media glyphs, over the section ribbon that
/// `LiveSetlistLanePainter` draws across the top of a song lane.
struct LiveSectionRibbonLabels: View {
    /// The in-to-out stretch the lane shows.
    let window: LiveLaneWindow
    let sections: [SongSection]
    let loopSectionIDs: Set<UUID>
    /// Width of the whole in-to-out lane.
    let contentWidth: CGFloat
    let height: CGFloat
    var showsMissingMediaWarning = false

    private var ribbonHeight: CGFloat {
        LiveSetlistWaveformMetrics.sectionRibbonHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(sections) { section in
                let startX = window.x(for: section.timelineStartSeconds, width: contentWidth)
                let endX = window.x(for: section.timelineEndSeconds, width: contentWidth)
                let segmentWidth = max(0, endX - startX)

                label(for: section, width: segmentWidth)
                    .offset(x: startX)

                if showsMissingMediaWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppTypography.Compact.overlayGlyph)
                        .foregroundStyle(AppColors.warning)
                        .frame(width: segmentWidth, height: max(0, height - ribbonHeight))
                        .offset(x: startX, y: ribbonHeight)
                }
            }
        }
        .frame(width: contentWidth, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func label(for section: SongSection, width: CGFloat) -> some View {
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
}
