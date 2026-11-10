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
/// Labeled times sit to the right of a tall tick; shorter ticks fill the gaps.
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

    private var pixelsPerSecond: CGFloat {
        contentWidth / CGFloat(safeDuration)
    }

    var body: some View {
        Canvas { context, size in
            let scale = TimeRulerScale(pixelsPerSecond: pixelsPerSecond)
            let mark = GraphicsContext.Shading.color(Color.secondary.opacity(0.5))
            let end = extendedMaximumTime
            guard scale.minor > 0, end >= 0 else { return }

            let subdivisions = max(1, Int((scale.major / scale.minor).rounded()))
            let stepCount = Int((end / scale.minor).rounded(.down))
            let minorTickHeight = min(4, size.height)
            let majorTickHeight = min(max(9, size.height * 0.46), size.height)

            var minorPath = Path()
            var majorPath = Path()
            for step in 0...stepCount {
                let time = Double(step) * scale.minor
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                guard x <= size.width + 1 else { break }
                let isMajor = step % subdivisions == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: isMajor ? majorTickHeight : minorTickHeight))
                if isMajor {
                    majorPath.addPath(tick)
                } else {
                    minorPath.addPath(tick)
                }
            }

            context.stroke(minorPath, with: mark, lineWidth: 1)
            context.stroke(majorPath, with: mark, lineWidth: 1)

            let labelFont = Font.system(size: 9, design: .monospaced)
            for step in stride(from: 0, through: stepCount, by: subdivisions) {
                let time = Double(step) * scale.minor
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                guard x <= size.width - 8 else { break }
                let label = context.resolve(
                    Text(Self.formatRulerTime(time, showsFraction: scale.major < 1))
                        .font(labelFont)
                        .foregroundStyle(.secondary)
                )
                context.draw(label, at: CGPoint(x: x + 4, y: 6), anchor: .topLeading)
            }
        }
        .frame(width: effectiveDisplayWidth, height: height)
        .background(Color.dawStickyRulerBackground)
        .allowsHitTesting(false)
    }

    private var extendedMaximumTime: TimeInterval {
        guard contentWidth > 0, effectiveDisplayWidth > contentWidth else { return safeDuration }
        return safeDuration * TimeInterval(effectiveDisplayWidth / contentWidth)
    }

    private static func formatRulerTime(_ value: TimeInterval, showsFraction: Bool) -> String {
        let clamped = max(0, value)
        let minutes = Int(clamped) / 60
        let seconds = clamped - Double(minutes * 60)
        if showsFraction {
            return String(format: "%d:%04.1f", minutes, seconds)
        }
        let wholeSeconds = Int((seconds + 0.000_1).rounded(.down))
        return String(format: "%d:%02d", minutes, wholeSeconds)
    }
}

/// Labeled spacing stays wide enough to read; unlabeled ticks subdivide it.
private struct TimeRulerScale {
    var major: TimeInterval
    var minor: TimeInterval

    init(pixelsPerSecond: CGFloat) {
        let pps = max(pixelsPerSecond, 0.001)
        let majors: [TimeInterval] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let raw = Double(140 / pps)
        major = majors.first(where: { $0 >= raw - 0.000_1 }) ?? 600
        let candidate = Self.preferredMinor(for: major)
        minor = CGFloat(candidate) * pps >= 8 ? candidate : major
    }

    private static func preferredMinor(for major: TimeInterval) -> TimeInterval {
        switch major {
        case 0.1: return 0.02
        case 0.2: return 0.05
        case 0.5: return 0.1
        case 1: return 0.2
        case 2: return 0.5
        case 5: return 1
        case 10: return 2
        case 15: return 5
        case 30: return 5
        case 60: return 10
        case 120: return 30
        case 300: return 60
        default: return 120
        }
    }
}
