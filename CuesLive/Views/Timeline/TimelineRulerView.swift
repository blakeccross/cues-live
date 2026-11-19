import SwiftUI

/// Vertical pieces of a measure line after clip headers have been cut out.
enum MeasureGridSpans {
    static func gaps(at x: CGFloat, in bands: [CGRect]) -> [ClosedRange<CGFloat>] {
        bands.compactMap { band in
            guard band.width > 0, band.height > 0, band.minX < x + 0.5, band.maxX > x - 0.5 else { return nil }
            return band.minY...band.maxY
        }
    }

    static func verticalSegments(
        from top: CGFloat,
        to bottom: CGFloat,
        skipping gaps: [ClosedRange<CGFloat>]
    ) -> [(CGFloat, CGFloat)] {
        guard bottom > top else { return [] }
        // A gap entirely outside the span would make an inverted range, so drop it first.
        let blocked = gaps
            .filter { $0.upperBound > top && $0.lowerBound < bottom }
            .map { max($0.lowerBound, top)...min($0.upperBound, bottom) }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<CGFloat>] = []
        for range in blocked {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var y = top
        var segments: [(CGFloat, CGFloat)] = []
        for range in merged {
            if range.lowerBound > y {
                segments.append((y, range.lowerBound))
            }
            y = max(y, range.upperBound)
        }
        if y < bottom {
            segments.append((y, bottom))
        }
        return segments
    }
}

struct TimelineRulerView: View {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let sections: [SongSection]
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    @Binding var selectedSectionID: UUID?
    @Binding var editingSectionID: UUID?
    let loopSectionIDs: Set<UUID>
    let sectionMarkerHeight: CGFloat
    let timeSignatureRulerHeight: CGFloat
    let tempoRulerHeight: CGFloat
    let isPlaying: Bool
    let onCueSection: (SongSection) -> Void
    let onToggleLoopSection: (SongSection) -> Void
    let onAddSection: (TimeInterval) -> Void
    let onRenameSection: (SongSection, String) -> Void
    let onManageSectionNames: () -> Void
    let onRemoveMarker: (SongSection) -> Void
    let previewSections: (SectionEdgeEdit) -> [SongSection]
    let onEditSectionEdge: (SectionEdgeEdit) -> Void
    let onTimeSignatureRulerTap: (TimeInterval) -> Void
    let onEditTimeSignatureMarker: (TimeSignatureChange) -> Void
    let onDeleteTimeSignatureMarker: (TimeSignatureChange) -> Void
    let onMoveTimeSignatureMarker: (TimeSignatureChange, TimeInterval) -> Void
    let onTempoRulerTap: (TimeInterval) -> Void
    let onEditTempoMarker: (TempoChange) -> Void
    let onDeleteTempoMarker: (TempoChange) -> Void
    let onMoveTempoMarker: (TempoChange, TimeInterval) -> Void
    let onTempoOperations: () -> Void

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var effectiveDisplayWidth: CGFloat {
        max(contentWidth, displayWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineTimeSignatureRulerView(
                duration: safeDuration,
                contentWidth: contentWidth,
                displayWidth: effectiveDisplayWidth,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                height: timeSignatureRulerHeight,
                onTap: onTimeSignatureRulerTap,
                onEditMarker: onEditTimeSignatureMarker,
                onDeleteMarker: onDeleteTimeSignatureMarker,
                onMoveMarker: onMoveTimeSignatureMarker
            )

            TimelineTempoRulerView(
                duration: safeDuration,
                contentWidth: contentWidth,
                displayWidth: effectiveDisplayWidth,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                height: tempoRulerHeight,
                onTap: onTempoRulerTap,
                onEditMarker: onEditTempoMarker,
                onDeleteMarker: onDeleteTempoMarker,
                onMoveMarker: onMoveTempoMarker,
                onTempoOperations: onTempoOperations
            )

            sectionMarkerRow
                .frame(width: effectiveDisplayWidth, height: sectionMarkerHeight)
        }
        .frame(width: effectiveDisplayWidth, alignment: .leading)
        .background(AppColors.Timeline.stickyRulerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.Timeline.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var sectionMarkerRow: some View {
        TimelineSectionMarkerRowView(
            sections: sections,
            duration: safeDuration,
            contentWidth: contentWidth,
            displayWidth: effectiveDisplayWidth,
            height: sectionMarkerHeight,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            selectedSectionID: $selectedSectionID,
            editingSectionID: $editingSectionID,
            loopSectionIDs: loopSectionIDs,
            isPlaying: isPlaying,
            onCueSection: onCueSection,
            onToggleLoopSection: onToggleLoopSection,
            onAddSection: onAddSection,
            onRenameSection: onRenameSection,
            onManageSectionNames: onManageSectionNames,
            onRemoveMarker: onRemoveMarker,
            previewSections: previewSections,
            onEditSectionEdge: onEditSectionEdge,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }
}
