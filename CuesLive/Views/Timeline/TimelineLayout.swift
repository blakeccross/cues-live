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
    /// Shared by every lane so a rubber band can span tracks.
    static let trackLanesCoordinateSpace = "trackLanes"
    static let clipHeaderHeight: CGFloat = 16
    /// Width of the trim hit target on each end of a clip header.
    static let clipTrimHandleWidth: CGFloat = 14
    static let laneSpacing: CGFloat = 0
    static let laneDividerHeight: CGFloat = 1
    static let clipCornerRadius: CGFloat = 0
    static let clipLaneInset: CGFloat = 0
    static let clipSelectionBorderWidth: CGFloat = 2
    static let clipBorderWidth: CGFloat = 1
    static let sectionMarkerHeight: CGFloat = 22
    static let timeSignatureRulerHeight: CGFloat = 24
    static let tempoRulerHeight: CGFloat = 24
    /// Minutes-and-seconds ruler. Pinned below the tracks, above the transport.
    static let rulerHeight: CGFloat = 22
    static let trackHeaderWidth: CGFloat = 204

    /// Section, time-signature, and tempo rulers above the tracks.
    static var topRulerHeight: CGFloat {
        sectionMarkerHeight + timeSignatureRulerHeight + tempoRulerHeight
    }

    static var rulerTotalHeight: CGFloat {
        topRulerHeight + rulerHeight
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
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)

        // Estimate stride from the first measure so we never allocate every
        // measure for multi‑hour songs just to throw most of them away.
        let firstMeasureTime = measureDuration(
            startingAt: 0,
            tickLength: tickLength(ofMeasure: 1, timeSignatureChanges: timeSignatureChanges),
            timeline: timeline
        )
        guard firstMeasureTime < timeLimit - 0.0001 else { return [] }
        let pixelsPerMeasure = CGFloat(firstMeasureTime) * contentWidth / CGFloat(safeDuration)
        let stride = max(1, Int(ceil(minimumPixelSpacing / max(pixelsPerMeasure, 0.001))))

        let rangeStart = max(0, visibleTimeRange?.lowerBound ?? 0)
        let rangeEnd = min(timeLimit, visibleTimeRange?.upperBound ?? timeLimit)
        guard rangeEnd > rangeStart else { return [] }

        let visiblePixelWidth = max(
            1,
            CGFloat((rangeEnd - rangeStart) / safeDuration) * contentWidth
        )
        let hardCap = Int(visiblePixelWidth / 4) + 8

        // Walk the measures once, accumulating time, rather than recomputing each
        // boundary from measure 1. Lines sit on measures 1 + k * stride, so tiles
        // drawn independently agree on which ones to show.
        var boundaries: [TimeInterval] = []
        var time: TimeInterval = 0
        var barTick = 0
        for measure in 1..<1_000_000 {
            if measure > 1, (measure - 1) % stride == 0 {
                guard time < timeLimit - 0.0001, time <= rangeEnd + firstMeasureTime else { break }
                if time >= rangeStart - firstMeasureTime {
                    boundaries.append(time)
                    if boundaries.count > hardCap { break }
                }
            }

            let length = tickLength(ofMeasure: measure, timeSignatureChanges: timeSignatureChanges)
            let duration = measureDuration(startingAt: barTick, tickLength: length, timeline: timeline)
            guard duration > 0 else { break }
            time += duration
            barTick += length
        }
        return boundaries
    }

    struct BeatGridTimes: Equatable {
        var beats: [TimeInterval]
        var subdivisions: [TimeInterval]
    }

    /// Which grid levels fit on screen. Soundcraft draws a level only when its steps
    /// are more than 7 points apart, so zooming in reveals beats and then eighths.
    struct LaneGridDetail: Equatable {
        var showsBeats: Bool
        var showsSubdivisions: Bool

        static let minimumSpacing: CGFloat = 7

        static func detail(pixelsPerSecond: CGFloat, fastestBPM: Double) -> LaneGridDetail {
            guard pixelsPerSecond > 0, fastestBPM > 0 else {
                return LaneGridDetail(showsBeats: false, showsSubdivisions: false)
            }
            let quarterPoints = CGFloat(60.0 / fastestBPM) * pixelsPerSecond
            return LaneGridDetail(
                showsBeats: quarterPoints > minimumSpacing,
                showsSubdivisions: quarterPoints > minimumSpacing * 2
            )
        }
    }

    /// Beat ticks (not the downbeat) and the halfway subdivision of each beat.
    /// A 4/4 bar yields quarters on `beats` and eighths on `subdivisions`.
    static func beatGridTimes(
        duration: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        visibleTimeRange: ClosedRange<TimeInterval>? = nil
    ) -> BeatGridTimes {
        let safeDuration = max(duration, 0.001)
        let rangeStart = max(0, visibleTimeRange?.lowerBound ?? 0)
        let rangeEnd = min(safeDuration, visibleTimeRange?.upperBound ?? safeDuration)
        guard rangeEnd > rangeStart, !tempoChanges.isEmpty else {
            return BeatGridTimes(beats: [], subdivisions: [])
        }
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)

        var beats: [TimeInterval] = []
        var subdivisions: [TimeInterval] = []
        var measure = 1
        var measureStart: TimeInterval = 0
        var barTick = 0

        while measure < 1_000_000, measureStart < safeDuration - 0.0001 {
            let lengthTicks = tickLength(ofMeasure: measure, timeSignatureChanges: timeSignatureChanges)
            let length = measureDuration(startingAt: barTick, tickLength: lengthTicks, timeline: timeline)
            guard length > 0 else { break }
            let measureEnd = measureStart + length
            if measureEnd < rangeStart {
                measureStart = measureEnd
                barTick += lengthTicks
                measure += 1
                continue
            }
            if measureStart > rangeEnd { break }

            let signature = numeratorDenominatorForMeasure(measure, changes: timeSignatureChanges)
            let beatsInMeasure = beatsPerMeasure(
                numerator: signature.numerator,
                denominator: signature.denominator
            )
            let beatCount = max(0, Int(beatsInMeasure.rounded(.down)))
            guard beatsInMeasure > 0, beatCount > 0 else {
                measureStart = measureEnd
                barTick += lengthTicks
                measure += 1
                continue
            }

            let beatDuration = length / beatsInMeasure
            let windowStart = rangeStart - beatDuration
            let windowEnd = rangeEnd + beatDuration
            for beatIndex in 1..<beatCount {
                let time = timeline.seconds(atTick: barTick + beatIndex * TempoChange.ticksPerQuarter)
                guard time < safeDuration - 0.0001 else { break }
                if time >= windowStart, time <= windowEnd {
                    beats.append(time)
                }
            }
            for step in 0..<beatCount {
                let time = timeline.seconds(atTick: barTick + step * TempoChange.ticksPerQuarter + TempoChange.ticksPerQuarter / 2)
                guard time < safeDuration - 0.0001 else { break }
                if time >= windowStart, time <= windowEnd {
                    subdivisions.append(time)
                }
            }

            measureStart = measureEnd
            barTick += lengthTicks
            measure += 1
        }

        return BeatGridTimes(beats: beats, subdivisions: subdivisions)
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
        let signature = changes.active(atMeasure: measure)
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
        return measureDuration(
            atMeasure: measure,
            tempoChanges: tempos,
            timeSignatureChanges: signatures
        )
    }

    /// Duration of `measure`, integrating any tempo events inside it.
    static func measureDuration(
        atMeasure measure: Int,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        guard bpmForMeasure(measure, tempoChanges: tempoChanges) > 0 else { return 0 }
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let barTick = TempoTimeline.tick(measure: measure, beatOffset: 0, timeSignatureChanges: timeSignatureChanges)
        let length = tickLength(ofMeasure: measure, timeSignatureChanges: timeSignatureChanges)
        return measureDuration(startingAt: barTick, tickLength: length, timeline: timeline)
    }

    private static func tickLength(
        ofMeasure measure: Int,
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Int {
        let signature = numeratorDenominatorForMeasure(measure, changes: timeSignatureChanges)
        let quarters = beatsPerMeasure(numerator: signature.numerator, denominator: signature.denominator)
        return max(0, Int((quarters * Double(TempoChange.ticksPerQuarter)).rounded()))
    }

    private static func measureDuration(
        startingAt barTick: Int,
        tickLength: Int,
        timeline: TempoTimeline
    ) -> TimeInterval {
        guard tickLength > 0, timeline.bpm(atTick: barTick) > 0 else { return 0 }
        let delta = timeline.seconds(atTick: barTick + tickLength) - timeline.seconds(atTick: barTick)
        guard delta.isFinite, delta > 0 else { return 0 }
        return delta
    }

    static func bpmForMeasure(
        _ measure: Int,
        tempoChanges: [TempoChange]
    ) -> Double {
        tempoChanges.activeBPM(atMeasure: measure)
    }

    static func timeAtStartOfMeasure(
        _ measure: Int,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        guard measure > 1 else { return 0 }
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let tick = TempoTimeline.tick(measure: measure, beatOffset: 0, timeSignatureChanges: timeSignatureChanges)
        return timeline.seconds(atTick: tick)
    }

    static func measureIndex(
        at time: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Int {
        guard time > 0, !tempoChanges.isEmpty else { return 1 }
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)

        var measure = 1
        var elapsed: TimeInterval = 0
        var barTick = 0

        while measure < 1_000_000 {
            let length = tickLength(ofMeasure: measure, timeSignatureChanges: timeSignatureChanges)
            let duration = measureDuration(startingAt: barTick, tickLength: length, timeline: timeline)
            guard duration > 0 else { return measure }
            if time < elapsed + duration - 0.0001 {
                return measure
            }
            elapsed += duration
            barTick += length
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
        guard !tempoChanges.isEmpty else { return TempoChange.defaultBPM }
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let tick = Int(timeline.tick(atSeconds: max(0, time)).rounded(.down))
        let bpm = timeline.bpm(atTick: tick)
        return bpm > 0 ? bpm : TempoChange.defaultBPM
    }

    /// Snaps a timeline time to the nearest beat grid line.
    static func snapToNearestBeat(
        _ time: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        guard time > 0, !tempoChanges.isEmpty else { return max(0, time) }
        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let quarters = timeline.tick(atSeconds: time) / Double(TempoChange.ticksPerQuarter)
        let measure = measureIndex(
            atBeat: quarters,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let startQuarters = beatAtStartOfMeasure(measure, timeSignatureChanges: timeSignatureChanges)
        let signature = numeratorDenominatorForMeasure(measure, changes: timeSignatureChanges)
        let beatsInMeasure = beatsPerMeasure(
            numerator: signature.numerator,
            denominator: signature.denominator
        )
        guard beatsInMeasure > 0 else { return max(0, time) }
        let maxBeatIndex = Double(max(0, Int(beatsInMeasure.rounded(.down))))
        let rounded = (quarters - startQuarters).rounded()
        let clamped = min(max(0, rounded), maxBeatIndex)
        let tick = TempoTimeline.tick(
            measure: measure,
            beatOffset: clamped,
            timeSignatureChanges: timeSignatureChanges
        )
        return timeline.seconds(atTick: tick)
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

        let timeline = TempoTimeline(tempoChanges: tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let quarters = timeline.tick(atSeconds: time) / Double(TempoChange.ticksPerQuarter)
        let bar = measureIndex(
            atBeat: quarters,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let startQuarters = beatAtStartOfMeasure(bar, timeSignatureChanges: timeSignatureChanges)
        let beatsElapsed = max(0, quarters - startQuarters)
        let signature = numeratorDenominatorForMeasure(bar, changes: timeSignatureChanges)
        let beatsInMeasure = beatsPerMeasure(
            numerator: signature.numerator,
            denominator: signature.denominator
        )

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
        let timeline = TempoTimeline(tempoChanges: markers, timeSignatureChanges: timeSignatureChanges)
        var segments: [Segment] = []

        for (index, marker) in markers.enumerated() {
            let startTick = TempoTimeline.tick(
                measure: marker.startMeasure,
                beatOffset: marker.beatOffset,
                timeSignatureChanges: timeSignatureChanges
            )
            let sourceStart = timeline.seconds(atTick: startTick)
            let sourceEnd: TimeInterval
            if index + 1 < markers.count {
                let next = markers[index + 1]
                let nextTick = TempoTimeline.tick(
                    measure: next.startMeasure,
                    beatOffset: next.beatOffset,
                    timeSignatureChanges: timeSignatureChanges
                )
                sourceEnd = timeline.seconds(atTick: nextTick)
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

    /// Wall-clock seconds playback needs to advance from source time `start` to `end`.
    func wallElapsed(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        guard end > start else { return 0 }
        guard !segments.isEmpty else { return end - start }

        var wall: TimeInterval = 0
        for segment in segments {
            let lower = max(start, segment.sourceStart)
            let upper = min(end, segment.sourceEnd)
            if upper > lower {
                wall += (upper - lower) / segment.ratio
            }
        }
        return wall
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
