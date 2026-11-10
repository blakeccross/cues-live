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

    private var sortedMarkers: [TimeSignatureChange] {
        timeSignatureChanges.sortedByMeasure
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.dawStickyRulerBackground)

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

                Text(segment.displayName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
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
                .fill(Color.dawTimelineDivider)
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

    private struct TimeSignatureSegment {
        let marker: TimeSignatureChange
        let startTime: TimeInterval
        let endTime: TimeInterval
        let displayName: String
    }

    private var timeSignatureSegments: [TimeSignatureSegment] {
        let markers = sortedMarkers
        guard !markers.isEmpty else { return [] }

        return markers.enumerated().map { index, marker in
            let startTime = MeasureTiming.timeAtStartOfMeasure(
                marker.startMeasure,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges
            )
            let endTime: TimeInterval
            if index + 1 < markers.count {
                endTime = MeasureTiming.timeAtStartOfMeasure(
                    markers[index + 1].startMeasure,
                    tempoChanges: tempoChanges,
                    timeSignatureChanges: timeSignatureChanges
                )
            } else {
                endTime = safeDuration
            }
            return TimeSignatureSegment(
                marker: marker,
                startTime: startTime,
                endTime: endTime,
                displayName: marker.displayName
            )
        }
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

    private var sortedMarkers: [TempoChange] {
        tempoChanges.sortedByMeasure
    }

    var body: some View {
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.dawStickyRulerBackground)
                .contextMenu {
                    Button("Tempo Operations…") {
                        onTempoOperations()
                    }
                }

            let segments = tempoSegments(timeline: timeline)
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

                if segmentWidth >= 28 {
                    Text(String(format: "%.0f", segment.bpm))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
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
                .fill(Color.dawTimelineDivider)
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

    private struct TempoSegment {
        let marker: TempoChange
        let startTime: TimeInterval
        let endTime: TimeInterval
        let bpm: Double
    }

    private func tempoSegments(timeline: TempoTimeline) -> [TempoSegment] {
        let markers = sortedMarkers
        guard !markers.isEmpty else { return [] }

        return markers.enumerated().map { index, marker in
            let startTick = TempoTimeline.tick(
                measure: marker.startMeasure,
                beatOffset: marker.beatOffset,
                timeSignatureChanges: timeSignatureChanges
            )
            let startTime = timeline.seconds(atTick: startTick)
            let endTime: TimeInterval
            if index + 1 < markers.count {
                let next = markers[index + 1]
                let nextTick = TempoTimeline.tick(
                    measure: next.startMeasure,
                    beatOffset: next.beatOffset,
                    timeSignatureChanges: timeSignatureChanges
                )
                endTime = timeline.seconds(atTick: nextTick)
            } else {
                endTime = safeDuration
            }
            return TempoSegment(marker: marker, startTime: startTime, endTime: endTime, bpm: marker.bpm)
        }
    }
}

private struct RulerMarkerDrag {
    let id: UUID
    var translation: CGFloat
}

/// Gray dot marking where a tempo or time signature change starts.
private struct RulerChangeDot: View {
    static let diameter: CGFloat = 6
    static let hitExtent: CGFloat = 14
    /// Distance from the change to the label: the dot's radius plus a small gap.
    static let labelInset: CGFloat = diameter / 2 + 4

    var body: some View {
        Circle()
            .fill(Color(white: 0.58))
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
