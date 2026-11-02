import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A timeline ruler selection spanning whole measures `[startMeasure, endMeasure)`.
struct MeasureRangeSelection: Equatable {
    var startMeasure: Int
    var endMeasure: Int
}

struct TimelineMeasureGridOverlay: View {
    let duration: TimeInterval
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    var contentWidth: CGFloat?
    var displayWidth: CGFloat?
    let rulerHeight: CGFloat

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
        Canvas { context, size in
            guard size.width > 0, size.height > 0, mappingWidth > 0 else { return }

            let rulerLineColor = Color.dawMeasureGridLine
            let trackLineColor = Color.dawMeasureGridLine.opacity(0.75)
            let rulerLineEnd = min(rulerHeight, size.height)

            for time in boundaries {
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: mappingWidth
                )
                guard x >= 0, x <= size.width else { continue }

                var rulerPath = Path()
                rulerPath.move(to: CGPoint(x: x, y: 0))
                rulerPath.addLine(to: CGPoint(x: x, y: rulerLineEnd))
                context.stroke(rulerPath, with: .color(rulerLineColor), lineWidth: 1)

                guard size.height > rulerLineEnd else { continue }

                var trackPath = Path()
                trackPath.move(to: CGPoint(x: x, y: rulerLineEnd))
                trackPath.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(trackPath, with: .color(trackLineColor), lineWidth: 1)
            }
        }
        .frame(width: canvasWidth > 0 ? canvasWidth : nil)
        .allowsHitTesting(false)
    }
}

struct TimelineRulerView: View {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let sections: [ArrangementDisplaySection]
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    let loopSlotIDs: Set<UUID>
    let sectionMarkerHeight: CGFloat
    let timeSignatureRulerHeight: CGFloat
    let tempoRulerHeight: CGFloat
    let rulerHeight: CGFloat
    let isPlaying: Bool
    let measureSelectionEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onSelectMeasures: (Int, Int) -> Void
    let onCueSection: (ArrangementDisplaySection) -> Void
    let onToggleLoopSection: (ArrangementDisplaySection) -> Void
    let onAddSection: (TimeInterval) -> Void
    let onAddSectionRange: (TimeInterval, TimeInterval) -> Void
    let snapSectionRange: (TimeInterval, TimeInterval) -> (TimeInterval, TimeInterval)
    let onRenameSection: (ArrangementDisplaySection) -> Void
    let onDeleteSection: (ArrangementDisplaySection) -> Void
    let onTimeSignatureRulerTap: (TimeInterval) -> Void
    let onEditTimeSignatureMarker: (TimeSignatureChange) -> Void
    let onDeleteTimeSignatureMarker: (TimeSignatureChange) -> Void
    let onTempoRulerTap: (TimeInterval) -> Void
    let onEditTempoMarker: (TempoChange) -> Void
    let onDeleteTempoMarker: (TempoChange) -> Void

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var effectiveDisplayWidth: CGFloat {
        max(contentWidth, displayWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionMarkerRow
                .frame(width: effectiveDisplayWidth, height: sectionMarkerHeight)

            TimelineTimeSignatureRulerView(
                duration: safeDuration,
                contentWidth: contentWidth,
                displayWidth: effectiveDisplayWidth,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                height: timeSignatureRulerHeight,
                onTap: onTimeSignatureRulerTap,
                onEditMarker: onEditTimeSignatureMarker,
                onDeleteMarker: onDeleteTimeSignatureMarker
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
                onDeleteMarker: onDeleteTempoMarker
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))

                ForEach(tickTimes, id: \.self) { time in
                    let x = TimelineLayout.xPosition(
                        for: time,
                        duration: safeDuration,
                        contentWidth: contentWidth
                    )

                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 1, height: 8)
                        Text(formatRulerTime(time))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .offset(x: x)
                }
            }
            .frame(width: effectiveDisplayWidth, height: rulerHeight)
            .contentShape(Rectangle())
            .gesture(seekGesture)
            #if os(macOS)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
        }
        .frame(width: effectiveDisplayWidth, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.dawTimelineDivider)
                .frame(height: 1)
        }
    }

    private static let measureDragThreshold: CGFloat = 4

    private var seekGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard measureSelectionEnabled else { return }
                guard abs(value.location.x - value.startLocation.x) >= Self.measureDragThreshold else { return }
                reportMeasureSelection(from: value.startLocation.x, to: value.location.x)
            }
            .onEnded { value in
                let dragDistance = abs(value.location.x - value.startLocation.x)
                if measureSelectionEnabled, dragDistance >= Self.measureDragThreshold {
                    reportMeasureSelection(from: value.startLocation.x, to: value.location.x)
                } else {
                    onSeek(rulerTime(at: value.location.x))
                }
            }
    }

    private func reportMeasureSelection(from startX: CGFloat, to endX: CGFloat) {
        let firstMeasure = measureIndex(at: startX)
        let secondMeasure = measureIndex(at: endX)
        let lower = min(firstMeasure, secondMeasure)
        let upper = max(firstMeasure, secondMeasure) + 1
        onSelectMeasures(lower, upper)
    }

    private func measureIndex(at x: CGFloat) -> Int {
        MeasureTiming.measureIndex(
            at: rulerTime(at: x),
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }

    private func rulerTime(at x: CGFloat) -> TimeInterval {
        let clampedX = min(max(0, x), effectiveDisplayWidth)
        return safeDuration * TimeInterval(clampedX / contentWidth)
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
            loopSlotIDs: loopSlotIDs,
            isPlaying: isPlaying,
            onCueSection: onCueSection,
            onToggleLoopSection: onToggleLoopSection,
            onAddSection: onAddSection,
            onAddSectionRange: onAddSectionRange,
            snapSectionRange: snapSectionRange,
            onRenameSection: onRenameSection,
            onDeleteSection: onDeleteSection
        )
    }

    private func formatRulerTime(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
