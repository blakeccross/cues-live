import Foundation

/// Stepwise tempo map. Each event holds its BPM until the next event, which is how
/// SoundCraft stores tempo — ramps are written as a run of these events.
struct TempoTimeline: Equatable {
    struct Point: Equatable {
        var tick: Int
        var bpm: Double
    }

    let points: [Point]
    /// Seconds elapsed at each point, so tick and time conversions binary-search.
    let elapsed: [Double]

    init(tempoChanges: [TempoChange], timeSignatureChanges: [TimeSignatureChange]) {
        let raw = tempoChanges
            .filter { $0.startMeasure >= 1 && $0.bpm.isFinite }
            .map { change in
                Point(
                    tick: max(0, Self.tick(measure: change.startMeasure, beatOffset: change.beatOffset, timeSignatureChanges: timeSignatureChanges)),
                    bpm: change.bpm
                )
            }
            .sorted { $0.tick < $1.tick }

        var points: [Point] = []
        for point in raw {
            if let last = points.last, last.tick == point.tick {
                points[points.count - 1] = point
            } else {
                points.append(point)
            }
        }

        if points.isEmpty {
            points = [Point(tick: 0, bpm: TempoChange.defaultBPM)]
        } else if points[0].tick > 0 {
            points.insert(Point(tick: 0, bpm: points[0].bpm), at: 0)
        }

        var elapsed: [Double] = []
        elapsed.reserveCapacity(points.count)
        var accumulated = 0.0
        for (index, point) in points.enumerated() {
            if index > 0 {
                let previous = points[index - 1]
                if previous.bpm > 0 {
                    accumulated += Double(point.tick - previous.tick) / Double(TempoChange.ticksPerQuarter) * 60.0 / previous.bpm
                }
            }
            elapsed.append(accumulated)
        }

        self.points = points
        self.elapsed = elapsed
    }

    func bpm(atTick tick: Int) -> Double {
        guard !points.isEmpty else { return TempoChange.defaultBPM }
        let index = segmentIndex(atOrBeforeTick: max(0, tick))
        return points[index].bpm
    }

    func seconds(atTick tick: Int) -> TimeInterval {
        guard !points.isEmpty else { return 0 }
        let target = max(0, tick)
        let index = segmentIndex(atOrBeforeTick: target)
        let point = points[index]
        guard point.bpm > 0 else { return elapsed[index] }
        return elapsed[index] + Double(target - point.tick) / Double(TempoChange.ticksPerQuarter) * 60.0 / point.bpm
    }

    /// Fractional tick at a timeline time. The inverse of `seconds(atTick:)`.
    func tick(atSeconds time: TimeInterval) -> Double {
        guard time > 0, let first = points.first, first.bpm > 0 else { return 0 }
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if elapsed[mid] <= time + 0.000_000_1 {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let point = points[low]
        guard point.bpm > 0 else { return Double(point.tick) }
        let into = max(0, time - elapsed[low])
        return Double(point.tick) + into * point.bpm * Double(TempoChange.ticksPerQuarter) / 60.0
    }

    static func tick(
        measure: Int,
        beatOffset: Double,
        timeSignatureChanges: [TimeSignatureChange]
    ) -> Int {
        let quarters = MeasureTiming.beatAtStartOfMeasure(max(1, measure), timeSignatureChanges: timeSignatureChanges)
            + max(0, beatOffset)
        return Int((quarters * Double(TempoChange.ticksPerQuarter)).rounded())
    }

    static func location(
        tick: Int,
        timeSignatureChanges: [TimeSignatureChange]
    ) -> (measure: Int, beatOffset: Double) {
        let quarters = Double(max(0, tick)) / Double(TempoChange.ticksPerQuarter)
        let measure = MeasureTiming.measureIndex(
            atBeat: quarters,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: TempoChange.defaultBPM)],
            timeSignatureChanges: timeSignatureChanges
        )
        let start = MeasureTiming.beatAtStartOfMeasure(measure, timeSignatureChanges: timeSignatureChanges)
        let offset = quarters - start
        return (measure, offset.isFinite ? max(0, offset) : 0)
    }

    private func segmentIndex(atOrBeforeTick tick: Int) -> Int {
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if points[mid].tick <= tick {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
