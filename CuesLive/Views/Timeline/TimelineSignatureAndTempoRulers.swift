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

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(timeSignatureColor(index).opacity(0.22))

                    Text(segment.displayName)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timeSignatureColor(index))
                        .padding(.horizontal, 4)
                        .frame(width: segmentWidth, alignment: .leading)
                        .lineLimit(1)
                }
                .frame(width: segmentWidth, height: height)
                .offset(x: startX)
            }

            ForEach(sortedMarkers) { marker in
                let time = MeasureTiming.timeAtStartOfMeasure(
                    marker.startMeasure,
                    tempoChanges: tempoChanges,
                    timeSignatureChanges: timeSignatureChanges
                )
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )

                Rectangle()
                    .fill(Color.indigo.opacity(0.85))
                    .frame(width: 2, height: height)
                    .offset(x: x)
                    .contextMenu {
                        Button("Edit Time Signature") {
                            onEditMarker(marker)
                        }
                        if marker.startMeasure > 1 {
                            Button("Delete Marker", role: .destructive) {
                                onDeleteMarker(marker)
                            }
                        }
                    }
            }
        }
        .frame(width: effectiveDisplayWidth, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    let time = TimelineLayout.time(
                        at: min(value.location.x, contentWidth),
                        duration: safeDuration,
                        contentWidth: contentWidth
                    )
                    onTap(time)
                }
        )
    }

    private struct TimeSignatureSegment {
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
                startTime: startTime,
                endTime: endTime,
                displayName: marker.displayName
            )
        }
    }

    private func timeSignatureColor(_ index: Int) -> Color {
        let colors: [Color] = [.indigo, .teal, .cyan, .blue, .mint]
        return colors[index % colors.count]
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
    let onTempoOperations: () -> Void

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

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(tempoColor(index).opacity(0.22))

                    if segmentWidth >= 28 {
                        Text(String(format: "%.0f", segment.bpm))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tempoColor(index))
                            .padding(.horizontal, 4)
                            .frame(width: segmentWidth, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .frame(width: segmentWidth, height: height)
                .offset(x: startX)
            }

            ForEach(sortedMarkers) { marker in
                let tick = TempoTimeline.tick(
                    measure: marker.startMeasure,
                    beatOffset: marker.beatOffset,
                    timeSignatureChanges: timeSignatureChanges
                )
                let time = timeline.seconds(atTick: tick)
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )

                Rectangle()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 2, height: height)
                    .offset(x: x)
                    .contextMenu {
                        Button("Edit Tempo") {
                            onEditMarker(marker)
                        }
                        Button("Tempo Operations…") {
                            onTempoOperations()
                        }
                        if !marker.isOrigin {
                            Button("Delete Marker", role: .destructive) {
                                onDeleteMarker(marker)
                            }
                        }
                    }
            }
        }
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
    }

    private struct TempoSegment {
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
            return TempoSegment(startTime: startTime, endTime: endTime, bpm: marker.bpm)
        }
    }

    private func tempoColor(_ index: Int) -> Color {
        let colors: [Color] = [.orange, .pink, .yellow, .red, .brown]
        return colors[index % colors.count]
    }
}
