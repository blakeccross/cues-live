import SwiftUI

struct TimelineMeasureGridOverlay: View {
    let duration: TimeInterval
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    var contentWidth: CGFloat?
    var displayWidth: CGFloat?
    let rulerHeight: CGFloat
    /// Draws the lane lines over the clips when the grid is shown.
    var showsThroughContent = false
    /// Opaque clip headers. Lane lines stop at these rects so the name bar stays solid.
    var headerBands: [CGRect] = []

    /// Set inside the editor lanes. The canvas then covers only the painted slice.
    @Environment(\.timelineScrollModel) private var scrollModel

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var mappingWidth: CGFloat {
        contentWidth ?? displayWidth ?? 0
    }

    private var canvasWidth: CGFloat {
        max(mappingWidth, displayWidth ?? mappingWidth)
    }

    /// Content x range the canvas occupies: the painted slice in the lanes, else everything.
    private var paintedSlice: ClosedRange<CGFloat> {
        guard let painted = scrollModel?.paintedRange else { return 0...canvasWidth }
        let lower = max(0, painted.lowerBound)
        let upper = min(canvasWidth, painted.upperBound)
        return upper > lower ? lower...upper : 0...0
    }

    private var extendedMaximumTime: TimeInterval {
        guard mappingWidth > 0, canvasWidth > mappingWidth else { return safeDuration }
        return safeDuration * TimeInterval(canvasWidth / mappingWidth)
    }

    private func time(atContentX x: CGFloat) -> TimeInterval {
        guard mappingWidth > 0 else { return 0 }
        return safeDuration * TimeInterval(x / mappingWidth)
    }

    /// Beats, then eighths, once each level is far enough apart to read.
    private func fineGridTimes(in slice: ClosedRange<CGFloat>) -> MeasureTiming.BeatGridTimes {
        let pixelsPerSecond = mappingWidth / CGFloat(safeDuration)
        let fastest = tempoChanges.map(\.bpm).filter { $0 > 0 }.max() ?? 0
        let detail = MeasureTiming.LaneGridDetail.detail(pixelsPerSecond: pixelsPerSecond, fastestBPM: fastest)
        guard detail.showsBeats else { return MeasureTiming.BeatGridTimes(beats: [], subdivisions: []) }
        let lower = time(atContentX: slice.lowerBound)
        let upper = min(extendedMaximumTime, time(atContentX: slice.upperBound))
        let grid = MeasureTiming.beatGridTimes(
            duration: safeDuration,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            visibleTimeRange: lower...max(lower, upper)
        )
        return MeasureTiming.BeatGridTimes(
            beats: grid.beats,
            subdivisions: detail.showsSubdivisions ? grid.subdivisions : []
        )
    }

    private func measureBoundaries(for contentWidth: CGFloat) -> [TimeInterval] {
        guard !tempoChanges.isEmpty, contentWidth > 0 else { return [] }
        return MeasureTiming.visibleMeasureBoundaries(
            duration: safeDuration,
            tempoChanges: tempoChanges,
            contentWidth: contentWidth,
            timeSignatureChanges: timeSignatureChanges,
            maximumTime: extendedMaximumTime
        )
    }

    var body: some View {
        let slice = paintedSlice
        let boundaries = measureBoundaries(for: mappingWidth)
        let fine = fineGridTimes(in: slice)
        Canvas { context, size in
            guard size.width > 0, size.height > 0, mappingWidth > 0 else { return }
            // Ticks are placed in content coordinates; the canvas starts at the slice. Only
            // the part AppKit is showing is stroked, since a scroll tick re-runs this closure.
            let visible = context.clipBoundingRect.offsetBy(dx: slice.lowerBound, dy: 0)
            let lower = max(slice.lowerBound, visible.minX - 1)
            let upper = min(slice.upperBound, visible.maxX + 1)
            guard upper > lower else { return }
            let stroked = lower...upper
            context.translateBy(x: -slice.lowerBound, y: 0)
            let size = CGSize(width: stroked.upperBound, height: size.height)

            let rulerLineColor = showsThroughContent ? AppColors.Timeline.barTick : AppColors.Timeline.measureGridLine
            let barColor = showsThroughContent ? AppColors.Timeline.barTick : AppColors.Timeline.rulerBarTick
            let beatColor = showsThroughContent ? AppColors.Timeline.beatTick : AppColors.Timeline.rulerBeatTick
            let subdivisionColor = showsThroughContent ? AppColors.Timeline.subdivisionTick : AppColors.Timeline.rulerBeatTick
            let rulerLineEnd = min(rulerHeight, size.height)

            for time in fine.subdivisions {
                strokeTick(at: time, in: &context, size: size, slice: stroked, rulerColor: subdivisionColor, trackColor: subdivisionColor, rulerLineEnd: rulerLineEnd)
            }
            for time in fine.beats {
                strokeTick(at: time, in: &context, size: size, slice: stroked, rulerColor: beatColor, trackColor: beatColor, rulerLineEnd: rulerLineEnd)
            }
            for time in boundaries {
                strokeTick(at: time, in: &context, size: size, slice: stroked, rulerColor: rulerLineColor, trackColor: barColor, rulerLineEnd: rulerLineEnd)
            }
        }
        .frame(width: canvasWidth > 0 ? slice.upperBound - slice.lowerBound : nil, alignment: .topLeading)
        .offset(x: slice.lowerBound)
        .frame(width: canvasWidth > 0 ? canvasWidth : nil, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func strokeTick(
        at time: TimeInterval,
        in context: inout GraphicsContext,
        size: CGSize,
        slice: ClosedRange<CGFloat>,
        rulerColor: Color,
        trackColor: Color,
        rulerLineEnd: CGFloat
    ) {
        let x = TimelineLayout.xPosition(
            for: time,
            duration: safeDuration,
            contentWidth: mappingWidth
        )
        guard x >= max(0, slice.lowerBound - 1), x <= size.width else { return }

        var rulerPath = Path()
        rulerPath.move(to: CGPoint(x: x, y: 0))
        rulerPath.addLine(to: CGPoint(x: x, y: rulerLineEnd))
        context.stroke(rulerPath, with: .color(rulerColor), lineWidth: 1)

        guard size.height > rulerLineEnd else { return }

        let gaps = showsThroughContent
            ? MeasureGridSpans.gaps(at: x, in: headerBands)
            : []
        for (start, end) in MeasureGridSpans.verticalSegments(from: rulerLineEnd, to: size.height, skipping: gaps) {
            var trackPath = Path()
            trackPath.move(to: CGPoint(x: x, y: start))
            trackPath.addLine(to: CGPoint(x: x, y: end))
            context.stroke(trackPath, with: .color(trackColor), lineWidth: 1)
        }
    }
}

/// Section-marker ticks. A dark gray stroke over the track viewport, from the top of
/// the lanes to the bottom of that area, on top of the clips.
struct TimelineSectionMarkerLines: View {
    let times: [TimeInterval]
    let duration: TimeInterval
    let contentWidth: CGFloat
    let horizontalScrollOffset: CGFloat
    let viewportWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0, contentWidth > 0 else { return }
            let safeDuration = max(duration, 0.001)
            let color = GraphicsContext.Shading.color(AppColors.Timeline.sectionMarkerLine)
            for time in times {
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                ) - horizontalScrollOffset
                guard x > 0, x < size.width else { continue }
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: color, lineWidth: 1)
            }
        }
        .frame(width: viewportWidth)
        .allowsHitTesting(false)
    }
}

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
        let blocked = gaps
            .map { max($0.lowerBound, top)...min($0.upperBound, bottom) }
            .filter { $0.upperBound > $0.lowerBound }
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
    let loopSectionIDs: Set<UUID>
    let sectionMarkerHeight: CGFloat
    let timeSignatureRulerHeight: CGFloat
    let tempoRulerHeight: CGFloat
    let isPlaying: Bool
    let onCueSection: (SongSection) -> Void
    let onToggleLoopSection: (SongSection) -> Void
    let onAddSection: (TimeInterval) -> Void
    let onRenameSection: (SongSection) -> Void
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
            loopSectionIDs: loopSectionIDs,
            isPlaying: isPlaying,
            onCueSection: onCueSection,
            onToggleLoopSection: onToggleLoopSection,
            onAddSection: onAddSection,
            onRenameSection: onRenameSection,
            onRemoveMarker: onRemoveMarker,
            previewSections: previewSections,
            onEditSectionEdge: onEditSectionEdge,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }
}
