import SwiftUI

struct TimelineMeasureGridOverlay: View {
    let duration: TimeInterval
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    var contentWidth: CGFloat?
    var displayWidth: CGFloat?
    let rulerHeight: CGFloat
    /// Draws the lane lines over the clips, the way Soundcraft draws a shown grid.
    var showsThroughContent = false
    /// Opaque clip headers. Lane lines stop at these rects so the name bar stays solid.
    var headerBands: [CGRect] = []

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var mappingWidth: CGFloat {
        contentWidth ?? displayWidth ?? 0
    }

    private var canvasWidth: CGFloat {
        max(mappingWidth, displayWidth ?? mappingWidth)
    }

    private var extendedMaximumTime: TimeInterval {
        guard mappingWidth > 0, canvasWidth > mappingWidth else { return safeDuration }
        return safeDuration * TimeInterval(canvasWidth / mappingWidth)
    }

    /// Beats, then eighths, once each level is far enough apart to read.
    private var fineGridTimes: MeasureTiming.BeatGridTimes {
        let pixelsPerSecond = mappingWidth / CGFloat(safeDuration)
        let fastest = tempoChanges.map(\.bpm).filter { $0 > 0 }.max() ?? 0
        let detail = MeasureTiming.LaneGridDetail.detail(pixelsPerSecond: pixelsPerSecond, fastestBPM: fastest)
        guard detail.showsBeats else { return MeasureTiming.BeatGridTimes(beats: [], subdivisions: []) }
        let grid = MeasureTiming.beatGridTimes(
            duration: safeDuration,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            visibleTimeRange: 0...extendedMaximumTime
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
        let boundaries = measureBoundaries(for: mappingWidth)
        let fine = fineGridTimes
        Canvas { context, size in
            guard size.width > 0, size.height > 0, mappingWidth > 0 else { return }

            let rulerLineColor = showsThroughContent ? Color.editorBarTick : Color.dawMeasureGridLine
            let barColor = showsThroughContent ? Color.editorBarTick : Color.dawMeasureGridLine.opacity(0.75)
            let beatColor = showsThroughContent ? Color.editorBeatTick : Color.dawMeasureGridLine.opacity(0.4)
            let subdivisionColor = showsThroughContent ? Color.editorSubdivisionTick : Color.dawMeasureGridLine.opacity(0.4)
            let rulerLineEnd = min(rulerHeight, size.height)

            for time in fine.subdivisions {
                strokeTick(at: time, in: &context, size: size, rulerColor: subdivisionColor, trackColor: subdivisionColor, rulerLineEnd: rulerLineEnd)
            }
            for time in fine.beats {
                strokeTick(at: time, in: &context, size: size, rulerColor: beatColor, trackColor: beatColor, rulerLineEnd: rulerLineEnd)
            }
            for time in boundaries {
                strokeTick(at: time, in: &context, size: size, rulerColor: rulerLineColor, trackColor: barColor, rulerLineEnd: rulerLineEnd)
            }
        }
        .frame(width: canvasWidth > 0 ? canvasWidth : nil)
        .allowsHitTesting(false)
    }

    private func strokeTick(
        at time: TimeInterval,
        in context: inout GraphicsContext,
        size: CGSize,
        rulerColor: Color,
        trackColor: Color,
        rulerLineEnd: CGFloat
    ) {
        let x = TimelineLayout.xPosition(
            for: time,
            duration: safeDuration,
            contentWidth: mappingWidth
        )
        guard x >= 0, x <= size.width else { return }

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
            let color = GraphicsContext.Shading.color(.sectionMarkerLine)
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
        .background(Color.dawStickyRulerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.dawTimelineDivider)
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
            onRemoveMarker: onRemoveMarker
        )
    }
}

/// Minutes-and-seconds ruler. Pinned below the tracks and above the transport.
struct TimelineTimeRulerView: View {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let height: CGFloat

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var effectiveDisplayWidth: CGFloat {
        max(contentWidth, displayWidth)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.dawStickyRulerBackground)

            ForEach(tickTimes, id: \.self) { time in
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )

                VStack(spacing: 1) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 1, height: 6)
                    Text(formatRulerTime(time))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .offset(x: x)
            }
        }
        .frame(width: effectiveDisplayWidth, height: height)
        .allowsHitTesting(false)
    }

    private var extendedMaximumTime: TimeInterval {
        guard contentWidth > 0, effectiveDisplayWidth > contentWidth else { return safeDuration }
        return safeDuration * TimeInterval(effectiveDisplayWidth / contentWidth)
    }

    private var tickTimes: [TimeInterval] {
        let tickInterval = tickIntervalSeconds
        let maximumTime = extendedMaximumTime
        var times: [TimeInterval] = []
        var time: TimeInterval = 0
        while time <= maximumTime + 0.0001 {
            times.append(time)
            time += tickInterval
        }
        return times
    }

    private var tickIntervalSeconds: TimeInterval {
        let pixelsPerTick: CGFloat = 80
        let pixelsPerSecond = contentWidth / safeDuration
        let rawInterval = Double(pixelsPerTick / pixelsPerSecond)
        let candidates: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300]
        return candidates.first(where: { $0 >= rawInterval }) ?? 300
    }

    private func formatRulerTime(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
