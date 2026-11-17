import SwiftUI

struct TimelineTimeSignatureRulerView: View {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let height: CGFloat
    let onTap: (TimeInterval) -> Void
    let onEditMarker: (TimeSignatureChange) -> Void
    let onDeleteMarker: (TimeSignatureChange) -> Void
    let onMoveMarker: (TimeSignatureChange, TimeInterval) -> Void

    @State private var drag: RulerMarkerDrag?

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var effectiveDisplayWidth: CGFloat {
        max(contentWidth, displayWidth)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(AppColors.Timeline.stickyRulerBackground)

            ForEach(Array(timeSignatureSegments.enumerated()), id: \.offset) { index, segment in
                let startX = TimelineLayout.xPosition(
                    for: segment.startTime,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                let endX = index + 1 == timeSignatureSegments.count
                    ? effectiveDisplayWidth
                    : TimelineLayout.xPosition(
                        for: segment.endTime,
                        duration: safeDuration,
                        contentWidth: contentWidth
                    )
                let segmentWidth = max(0, endX - startX)

                Text(segment.label)
                    .font(AppTypography.Compact.rulerValue)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, RulerChangeDot.labelInset)
                    .frame(width: segmentWidth, height: height, alignment: .leading)
                    .clipped()
                    .offset(x: startX + dragOffset(for: segment.marker.id))
            }

            ForEach(timeSignatureSegments, id: \.marker.id) { segment in
                let startX = xPosition(for: segment.startTime)
                RulerChangeMarker(
                    x: startX,
                    markerID: segment.marker.id,
                    canDrag: segment.marker.startMeasure > 1,
                    drag: $drag,
                    coordinateSpace: Self.dragSpace,
                    snappedTime: snappedTime(forDragEndX:),
                    xPosition: xPosition(for:),
                    onDrop: { onMoveMarker(segment.marker, $0) }
                ) {
                    Button("Edit Time Signature") {
                        onEditMarker(segment.marker)
                    }
                    if segment.marker.startMeasure > 1 {
                        Button("Delete Marker", role: .destructive) {
                            onDeleteMarker(segment.marker)
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: Self.dragSpace)
        .frame(width: effectiveDisplayWidth, height: height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 2)
                .onEnded { event in
                    let time = TimelineLayout.time(
                        at: min(event.location.x, contentWidth),
                        duration: safeDuration,
                        contentWidth: contentWidth
                    )
                    onTap(time)
                }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.Timeline.divider)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private static let dragSpace = "timeSignatureRuler"

    private func xPosition(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: safeDuration, contentWidth: contentWidth)
    }

    private func dragOffset(for id: UUID) -> CGFloat {
        guard drag?.id == id else { return 0 }
        return drag?.translation ?? 0
    }

    /// Snaps a dragged time-signature marker onto a bar line.
    private func snappedTime(forDragEndX x: CGFloat) -> TimeInterval {
        let time = TimelineLayout.time(
            at: min(max(0, x), contentWidth),
            duration: safeDuration,
            contentWidth: contentWidth
        )
        return MeasureTiming.nearestMeasureBoundary(
            to: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        ).time
    }

    private var timeSignatureSegments: [TimelineRulerSegment<TimeSignatureChange>] {
        TimelineRulerSegment.segments(
            timeSignatureChanges: timeSignatureChanges,
            tempoChanges: tempoChanges,
            duration: safeDuration
        )
    }
}

struct TimelineTempoRulerView: View {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let height: CGFloat
    let onTap: (TimeInterval) -> Void
    let onEditMarker: (TempoChange) -> Void
    let onDeleteMarker: (TempoChange) -> Void
    let onMoveMarker: (TempoChange, TimeInterval) -> Void
    let onTempoOperations: () -> Void

    @State private var drag: RulerMarkerDrag?

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var effectiveDisplayWidth: CGFloat {
        max(contentWidth, displayWidth)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(AppColors.Timeline.stickyRulerBackground)
                .contextMenu {
                    Button("Tempo Operations…") {
                        onTempoOperations()
                    }
                }

            let segments = TimelineRulerSegment.segments(
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                duration: safeDuration
            )
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let startX = TimelineLayout.xPosition(
                    for: segment.startTime,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                let endX = index + 1 == segments.count
                    ? effectiveDisplayWidth
                    : TimelineLayout.xPosition(
                        for: segment.endTime,
                        duration: safeDuration,
                        contentWidth: contentWidth
                    )
                let segmentWidth = max(0, endX - startX)

                if segmentWidth >= TimelineRulerSegment<TempoChange>.minimumLabeledWidth {
                    Text(segment.label)
                        .font(AppTypography.Compact.rulerValue)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, RulerChangeDot.labelInset)
                        .frame(width: segmentWidth, height: height, alignment: .leading)
                        .clipped()
                        .offset(x: startX + dragOffset(for: segment.marker.id))
                }
            }

            ForEach(segments, id: \.marker.id) { segment in
                let startX = xPosition(for: segment.startTime)
                RulerChangeMarker(
                    x: startX,
                    markerID: segment.marker.id,
                    canDrag: !segment.marker.isOrigin,
                    drag: $drag,
                    coordinateSpace: Self.dragSpace,
                    snappedTime: snappedTime(forDragEndX:),
                    xPosition: xPosition(for:),
                    onDrop: { onMoveMarker(segment.marker, $0) }
                ) {
                    Button("Edit Tempo") {
                        onEditMarker(segment.marker)
                    }
                    Button("Tempo Operations…") {
                        onTempoOperations()
                    }
                    if !segment.marker.isOrigin {
                        Button("Delete Marker", role: .destructive) {
                            onDeleteMarker(segment.marker)
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: Self.dragSpace)
        .frame(width: effectiveDisplayWidth, height: height)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture(count: 2)
                .onEnded { event in
                    let time = TimelineLayout.time(
                        at: min(event.location.x, contentWidth),
                        duration: safeDuration,
                        contentWidth: contentWidth
                    )
                    onTap(time)
                }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.Timeline.divider)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private static let dragSpace = "tempoRuler"

    private func xPosition(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: safeDuration, contentWidth: contentWidth)
    }

    private func dragOffset(for id: UUID) -> CGFloat {
        guard drag?.id == id else { return 0 }
        return drag?.translation ?? 0
    }

    /// Snaps a dragged tempo marker onto a beat.
    private func snappedTime(forDragEndX x: CGFloat) -> TimeInterval {
        let time = TimelineLayout.time(
            at: min(max(0, x), contentWidth),
            duration: safeDuration,
            contentWidth: contentWidth
        )
        return MeasureTiming.snapToNearestBeat(
            time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }
}

private struct RulerMarkerDrag {
    let id: UUID
    var translation: CGFloat
}

/// Gray dot marking where a tempo or time signature change starts.
struct RulerChangeDot: View {
    static let diameter: CGFloat = 6
    static let hitExtent: CGFloat = 14
    /// Distance from the change to the label: the dot's radius plus a small gap.
    static let labelInset: CGFloat = diameter / 2 + 4

    var body: some View {
        Circle()
            .fill(AppColors.Timeline.rulerChangeMarker)
            .frame(width: Self.diameter, height: Self.diameter)
            .frame(width: Self.hitExtent, height: Self.hitExtent)
            .contentShape(Rectangle())
    }
}

/// Centers a change dot on its time and drags it along the ruler.
private struct RulerChangeMarker<Menu: View>: View {
    let x: CGFloat
    let markerID: UUID
    let canDrag: Bool
    @Binding var drag: RulerMarkerDrag?
    let coordinateSpace: String
    let snappedTime: (CGFloat) -> TimeInterval
    let xPosition: (TimeInterval) -> CGFloat
    let onDrop: (TimeInterval) -> Void
    @ViewBuilder let menu: () -> Menu

    private var translation: CGFloat {
        guard drag?.id == markerID else { return 0 }
        return drag?.translation ?? 0
    }

    var body: some View {
        RulerChangeDot()
            .contextMenu { menu() }
            .highPriorityGesture(dragGesture)
            .offset(x: x - RulerChangeDot.hitExtent / 2 + translation)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                guard canDrag else { return }
                let snappedX = xPosition(snappedTime(value.location.x))
                drag = RulerMarkerDrag(id: markerID, translation: snappedX - x)
            }
            .onEnded { value in
                guard canDrag else { return }
                let time = snappedTime(value.location.x)
                drag = nil
                onDrop(time)
            }
    }
}
