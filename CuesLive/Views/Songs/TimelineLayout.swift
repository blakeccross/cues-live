import AVFoundation
import CoreGraphics
import Foundation

enum AudioTimelineMath {
    /// Converts a timeline offset (relative to trim start) to an absolute file frame index.
    static func frame(
        timelineOffset: TimeInterval,
        trimStart: TimeInterval,
        sampleRate: Double
    ) -> AVAudioFramePosition {
        AVAudioFramePosition(((trimStart + timelineOffset) * sampleRate).rounded(.toNearestOrAwayFromZero))
    }

    /// Snaps a timeline time to the nearest sample boundary.
    static func quantize(_ seconds: TimeInterval, sampleRate: Double) -> TimeInterval {
        guard sampleRate > 0 else { return seconds }
        return Double((seconds * sampleRate).rounded(.toNearestOrAwayFromZero)) / sampleRate
    }

    static func timelineOffset(
        fromFrame frame: AVAudioFramePosition,
        trimStart: TimeInterval,
        sampleRate: Double
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(frame) / sampleRate - trimStart
    }
}

enum TimelineLayout {
    static let basePixelsPerSecond: CGFloat = 6
    static let maxZoom: CGFloat = 8
    static let minimumContentWidth: CGFloat = 320

    /// Most zoomed-out level: entire timeline fits in the visible viewport when possible.
    static func minZoom(duration: TimeInterval, viewportWidth: CGFloat) -> CGFloat {
        guard duration > 0, viewportWidth > 0 else { return 1 }
        let naturalWidth = CGFloat(max(duration, 1)) * basePixelsPerSecond
        let floorZoom = minimumContentWidth / naturalWidth
        let fitZoom = viewportWidth / naturalWidth
        if naturalWidth > viewportWidth {
            return max(floorZoom, fitZoom)
        }
        return max(floorZoom, 1)
    }

    static let laneHeight: CGFloat = 104
    static let clipHeaderHeight: CGFloat = 16
    static let laneSpacing: CGFloat = 4
    static let clipCornerRadius: CGFloat = 6
    static let clipLaneInset: CGFloat = 3
    static let clipSelectionBorderWidth: CGFloat = 2
    static let clipBorderWidth: CGFloat = 1
    static let sectionMarkerHeight: CGFloat = 22
    static let timeSignatureRulerHeight: CGFloat = 24
    static let tempoRulerHeight: CGFloat = 24
    static let rulerHeight: CGFloat = 28
    static let trackHeaderWidth: CGFloat = 204

    static var rulerTotalHeight: CGFloat {
        sectionMarkerHeight + timeSignatureRulerHeight + tempoRulerHeight + rulerHeight
    }

    static func pixelsPerSecond(zoom: CGFloat) -> CGFloat {
        basePixelsPerSecond * zoom
    }

    static func contentWidth(for duration: TimeInterval, zoom: CGFloat = 1) -> CGFloat {
        max(minimumContentWidth, CGFloat(max(duration, 1)) * pixelsPerSecond(zoom: zoom))
    }

    static func xPosition(for time: TimeInterval, duration: TimeInterval, contentWidth: CGFloat) -> CGFloat {
        let safeDuration = max(duration, 0.001)
        return contentWidth * CGFloat(max(0, time) / safeDuration)
    }

    static func time(at x: CGFloat, duration: TimeInterval, contentWidth: CGFloat) -> TimeInterval {
        let safeDuration = max(duration, 0.001)
        guard contentWidth > 0 else { return 0 }
        let clampedX = min(max(0, x), contentWidth)
        return safeDuration * TimeInterval(clampedX / contentWidth)
    }
}

enum MeasureTiming {
    static let defaultNumerator = 4
    static let defaultDenominator = 4

    static func beatsPerMeasure(numerator: Int, denominator: Int) -> Double {
        guard numerator > 0, denominator > 0 else { return 4 }
        return Double(numerator) * 4.0 / Double(denominator)
    }

    /// Measure boundary times for grid lines, thinning when zoomed out.
    static func visibleMeasureBoundaries(
        duration: TimeInterval,
        bpm: Double,
        contentWidth: CGFloat,
        timeSignatureChanges: [TimeSignatureChange] = [],
        minimumPixelSpacing: CGFloat = 10
    ) -> [TimeInterval] {
        visibleMeasureBoundaries(
            duration: duration,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: bpm)],
            contentWidth: contentWidth,
            timeSignatureChanges: timeSignatureChanges,
            minimumPixelSpacing: minimumPixelSpacing
        )
    }

    static func visibleMeasureBoundaries(
        duration: TimeInterval,
        tempoChanges: [TempoChange],
        contentWidth: CGFloat,
        timeSignatureChanges: [TimeSignatureChange],
        minimumPixelSpacing: CGFloat = 10,
        maximumTime: TimeInterval? = nil,
        /// When set, only emit boundaries that fall inside this timeline window
        /// (plus one stride of padding). Used by viewport-tiled setlist lanes so
        /// long songs do not allocate thousands of unused lines.
        visibleTimeRange: ClosedRange<TimeInterval>? = nil
    ) -> [TimeInterval] {
        let safeDuration = max(duration, 0.001)
        let timeLimit = max(safeDuration, maximumTime ?? safeDuration)
        guard safeDuration > 0, contentWidth > 0, !tempoChanges.isEmpty else { return [] }

        // Estimate stride from the first measure so we never allocate every
        // measure for multi‑hour songs just to throw most of them away.
        let firstMeasureTime = timeAtStartOfMeasure(
            2,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        guard firstMeasureTime < timeLimit - 0.0001 else { return [] }
        let pixelsPerMeasure = CGFloat(firstMeasureTime) * contentWidth / CGFloat(safeDuration)
        let stride = max(1, Int(ceil(minimumPixelSpacing / max(pixelsPerMeasure, 0.001))))

        let rangeStart = max(0, visibleTimeRange?.lowerBound ?? 0)
        let rangeEnd = min(timeLimit, visibleTimeRange?.upperBound ?? timeLimit)
        guard rangeEnd > rangeStart else { return [] }

        // Jump near the visible window instead of walking from measure 1.
        var measure = 1 + stride
        if rangeStart > firstMeasureTime {
            let estimated = Int(rangeStart / max(firstMeasureTime, 0.0001))
            measure = max(1 + stride, (estimated / stride) * stride)
        }

        // Walk backward one stride so the first visible line is included.
        if measure > 1 + stride {
            measure = max(1 + stride, measure - stride)
        }

        let visiblePixelWidth = max(
            1,
            CGFloat((rangeEnd - rangeStart) / safeDuration) * contentWidth
        )
        let hardCap = Int(visiblePixelWidth / 4) + 8

        var boundaries: [TimeInterval] = []
        while true {
            let time = timeAtStartOfMeasure(
                measure,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges
            )
            guard time < timeLimit - 0.0001 else { break }
            if time > rangeEnd + firstMeasureTime { break }
            if time >= rangeStart - firstMeasureTime {
                boundaries.append(time)
            }
            measure += stride
            if boundaries.count > hardCap { break }
        }
        return boundaries
    }

    static func beatAtStartOfMeasure(
        _ measure: Int,
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Double {
        guard measure > 1 else { return 0 }

        var beats: Double = 0
        for index in 1..<measure {
            let signature = numeratorDenominatorForMeasure(index, changes: timeSignatureChanges)
            beats += beatsPerMeasure(numerator: signature.numerator, denominator: signature.denominator)
        }
        return beats
    }

    /// Returns the measure whose start beat is nearest to `beat`, within `toleranceBeats`.
    static func snappedMeasure(
        forBeat beat: Double,
        timeSignatureChanges: [TimeSignatureChange],
        toleranceBeats: Double = 1.5
    ) -> Int? {
        guard beat > 0, !timeSignatureChanges.isEmpty else { return beat > 0 ? nil : 1 }

        let measure = measureIndex(
            atBeat: beat,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: TempoChange.defaultBPM)],
            timeSignatureChanges: timeSignatureChanges
        )
        let start = beatAtStartOfMeasure(measure, timeSignatureChanges: timeSignatureChanges)
        if abs(beat - start) <= toleranceBeats {
            return measure
        }

        let nextMeasure = measure + 1
        let nextStart = beatAtStartOfMeasure(nextMeasure, timeSignatureChanges: timeSignatureChanges)
        if abs(beat - nextStart) <= toleranceBeats {
            return nextMeasure
        }

        return nil
    }

    static func numeratorDenominatorForMeasure(
        _ measure: Int,
        changes: [TimeSignatureChange]
    ) -> (numerator: Int, denominator: Int) {
        let signature = changes.sortedByMeasure.active(atMeasure: measure)
        return (
            signature?.numerator ?? defaultNumerator,
            signature?.denominator ?? defaultDenominator
        )
    }

    static func measureDuration(
        bpm: Double,
        numerator: Int = defaultNumerator,
        denominator: Int = defaultDenominator
    ) -> TimeInterval {
        guard bpm > 0 else { return 0 }
        return beatsPerMeasure(numerator: numerator, denominator: denominator) * 60.0 / bpm
    }

    /// Duration of one measure ending at `timelineSeconds`, using the active tempo/meter.
    static func measureLeadDuration(
        endingAt timelineSeconds: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        let safeTime = max(0, timelineSeconds)
        let tempos = tempoChanges.isEmpty
            ? [TempoChange(startMeasure: 1, bpm: TempoChange.defaultBPM)]
            : tempoChanges
        let signatures = timeSignatureChanges.isEmpty
            ? [
                TimeSignatureChange(
                    numerator: defaultNumerator,
                    denominator: defaultDenominator,
                    startMeasure: 1
                )
            ]
            : timeSignatureChanges

        let measure = measureIndex(
            at: max(0, safeTime - 0.0001),
            tempoChanges: tempos,
            timeSignatureChanges: signatures
        )
        let bpm = bpmForMeasure(measure, tempoChanges: tempos)
        let signature = numeratorDenominatorForMeasure(measure, changes: signatures)
        return measureDuration(
            bpm: bpm,
            numerator: signature.numerator,
            denominator: signature.denominator
        )
    }

    static func bpmForMeasure(
        _ measure: Int,
        tempoChanges: [TempoChange]
    ) -> Double {
        tempoChanges.sortedByMeasure.active(atMeasure: measure)?.bpm ?? TempoChange.defaultBPM
    }

    static func timeAtStartOfMeasure(
        _ measure: Int,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        guard measure > 1 else { return 0 }

        var time: TimeInterval = 0
        for index in 1..<measure {
            let bpm = bpmForMeasure(index, tempoChanges: tempoChanges)
            let signature = numeratorDenominatorForMeasure(index, changes: timeSignatureChanges)
            time += measureDuration(
                bpm: bpm,
                numerator: signature.numerator,
                denominator: signature.denominator
            )
        }
        return time
    }

    static func measureIndex(
        at time: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Int {
        guard time > 0, !tempoChanges.isEmpty else { return 1 }

        var measure = 1
        var elapsed: TimeInterval = 0

        while measure < 1_000_000 {
            let bpm = bpmForMeasure(measure, tempoChanges: tempoChanges)
            let signature = numeratorDenominatorForMeasure(measure, changes: timeSignatureChanges)
            let duration = measureDuration(
                bpm: bpm,
                numerator: signature.numerator,
                denominator: signature.denominator
            )
            guard duration > 0 else { return measure }
            if time < elapsed + duration - 0.0001 {
                return measure
            }
            elapsed += duration
            measure += 1
        }

        return measure
    }

    static func measureIndex(
        atBeat beat: Double,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Int {
        guard beat > 0, !tempoChanges.isEmpty else { return 1 }

        var measure = 1
        var elapsedBeats: Double = 0

        while measure < 1_000_000 {
            let signature = numeratorDenominatorForMeasure(measure, changes: timeSignatureChanges)
            let beatsInMeasure = beatsPerMeasure(
                numerator: signature.numerator,
                denominator: signature.denominator
            )
            guard beatsInMeasure > 0 else { return measure }
            if beat < elapsedBeats + beatsInMeasure - 0.0001 {
                return measure
            }
            elapsedBeats += beatsInMeasure
            measure += 1
        }

        return measure
    }

    static func activeBPM(
        at time: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Double {
        let measure = measureIndex(
            at: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        return bpmForMeasure(measure, tempoChanges: tempoChanges)
    }

    /// Snaps a timeline time to the nearest beat grid line.
    static func snapToNearestBeat(
        _ time: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        guard time > 0, !tempoChanges.isEmpty else { return max(0, time) }

        let measure = measureIndex(
            at: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let measureStart = timeAtStartOfMeasure(
            measure,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let bpm = bpmForMeasure(measure, tempoChanges: tempoChanges)
        let signature = numeratorDenominatorForMeasure(measure, changes: timeSignatureChanges)
        let beatsInMeasure = beatsPerMeasure(
            numerator: signature.numerator,
            denominator: signature.denominator
        )
        let beatDuration = measureDuration(
            bpm: bpm,
            numerator: signature.numerator,
            denominator: signature.denominator
        ) / beatsInMeasure

        guard beatDuration > 0 else { return max(0, time) }

        let timeInMeasure = max(0, time - measureStart)
        let beatIndex = (timeInMeasure / beatDuration).rounded()
        let maxBeatIndex = max(0, Int(beatsInMeasure.rounded(.down)))
        let clampedBeatIndex = min(max(0, Int(beatIndex)), maxBeatIndex)
        return measureStart + TimeInterval(clampedBeatIndex) * beatDuration
    }

    static func snapTimelineRangeToGrid(
        start: TimeInterval,
        end: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> (start: TimeInterval, end: TimeInterval) {
        let snappedStart = snapToNearestBeat(start, tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let snappedEnd = snapToNearestBeat(end, tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        if snappedStart <= snappedEnd {
            return (snappedStart, snappedEnd)
        }
        return (snappedEnd, snappedStart)
    }

    static func nearestMeasureBoundary(
        to time: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> (measure: Int, time: TimeInterval) {
        let measure = measureIndex(
            at: max(0, time),
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let start = timeAtStartOfMeasure(
            measure,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let nextMeasure = measure + 1
        let nextStart = timeAtStartOfMeasure(
            nextMeasure,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )

        if time - start <= nextStart - time {
            return (measure, start)
        }
        return (nextMeasure, nextStart)
    }

    struct MeasurePosition: Equatable {
        let bar: Int
        let beat: Int
        let subdivision: Int
    }

    static func position(
        at time: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> MeasurePosition {
        guard time > 0, !tempoChanges.isEmpty else {
            return MeasurePosition(bar: 1, beat: 1, subdivision: 1)
        }

        let bar = measureIndex(
            at: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let measureStart = timeAtStartOfMeasure(
            bar,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let timeInMeasure = max(0, time - measureStart)
        let bpm = bpmForMeasure(bar, tempoChanges: tempoChanges)
        let signature = numeratorDenominatorForMeasure(bar, changes: timeSignatureChanges)
        let beatsInMeasure = beatsPerMeasure(
            numerator: signature.numerator,
            denominator: signature.denominator
        )

        let beatsElapsed = timeInMeasure * bpm / 60.0
        let wholeBeats = Int(floor(beatsElapsed))
        let maxBeat = max(1, Int(beatsInMeasure.rounded(.down)))
        let beat = min(max(wholeBeats + 1, 1), maxBeat)

        let fractionalPart = beatsElapsed - floor(beatsElapsed)
        let subdivision = min(4, max(1, Int(floor(fractionalPart * 4)) + 1))

        return MeasurePosition(bar: bar, beat: beat, subdivision: subdivision)
    }

    static func formatPosition(_ position: MeasurePosition) -> String {
        "\(position.bar).\(position.beat).\(position.subdivision)"
    }

    static func formatTransportPosition(_ position: MeasurePosition) -> String {
        "\(position.bar) \(position.beat) \(position.subdivision)"
    }

    static func formatElapsedTime(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

/// Precomputed tempo segments for O(markers) playback integration on the audio thread.
struct TempoPlaybackMap: Sendable {
    struct Segment: Sendable {
        let sourceStart: TimeInterval
        let sourceEnd: TimeInterval
        let ratio: Double
    }

    let segments: [Segment]

    static let defaultMaxSourceTime: TimeInterval = 86_400

    static func build(
        tempoChanges: [TempoChange],
        referenceBPM: Double,
        timeSignatureChanges: [TimeSignatureChange],
        maxSourceTime: TimeInterval = defaultMaxSourceTime
    ) -> TempoPlaybackMap {
        guard referenceBPM > 0, !tempoChanges.isEmpty else {
            return TempoPlaybackMap(segments: [])
        }

        let markers = tempoChanges.sortedByMeasure
        var segments: [Segment] = []

        for (index, marker) in markers.enumerated() {
            let sourceStart = MeasureTiming.timeAtStartOfMeasure(
                marker.startMeasure,
                tempoChanges: markers,
                timeSignatureChanges: timeSignatureChanges
            )
            let sourceEnd: TimeInterval
            if index + 1 < markers.count {
                sourceEnd = MeasureTiming.timeAtStartOfMeasure(
                    markers[index + 1].startMeasure,
                    tempoChanges: markers,
                    timeSignatureChanges: timeSignatureChanges
                )
            } else {
                sourceEnd = max(maxSourceTime, sourceStart + 1)
            }

            guard sourceEnd > sourceStart else { continue }
            segments.append(
                Segment(
                    sourceStart: sourceStart,
                    sourceEnd: sourceEnd,
                    ratio: marker.bpm / referenceBPM
                )
            )
        }

        return TempoPlaybackMap(segments: segments)
    }

    func sourceTimeAfterWallElapsed(from anchor: TimeInterval, wallElapsed: TimeInterval) -> TimeInterval {
        guard wallElapsed > 0, !segments.isEmpty else { return max(0, anchor) }

        var wall = wallElapsed
        var source = max(0, anchor)
        var segmentIndex = segmentIndex(for: source)

        while wall > 0.000_000_1, segmentIndex < segments.count {
            let segment = segments[segmentIndex]
            source = max(source, segment.sourceStart)

            let remainingSource = segment.sourceEnd - source
            guard remainingSource > 0 else {
                segmentIndex += 1
                continue
            }

            let wallForRemainder = remainingSource / segment.ratio
            if wall <= wallForRemainder + 0.000_000_1 {
                return min(segment.sourceEnd, source + wall * segment.ratio)
            }

            wall -= wallForRemainder
            source = segment.sourceEnd
            segmentIndex += 1
        }

        return source
    }

    func ratio(at sourceTime: TimeInterval) -> Double {
        guard !segments.isEmpty else { return 1.0 }
        let time = max(0, sourceTime)
        if let segment = segments.last(where: { time >= $0.sourceStart - 0.000_1 && time < $0.sourceEnd - 0.000_1 }) {
            return segment.ratio
        }
        return segments.last?.ratio ?? 1.0
    }

    private func segmentIndex(for sourceTime: TimeInterval) -> Int {
        guard !segments.isEmpty else { return 0 }
        for (index, segment) in segments.enumerated() {
            if sourceTime < segment.sourceEnd - 0.000_1 {
                return index
            }
        }
        return segments.count - 1
    }
}
