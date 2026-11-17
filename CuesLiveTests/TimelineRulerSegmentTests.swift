import XCTest
@testable import CuesLive

final class TimelineRulerSegmentTests: XCTestCase {
    /// 120 BPM in 4/4: two seconds a bar.
    private let tempo = [TempoChange(startMeasure: 1, bpm: 120)]

    func testMeterSegmentsRunFromEachChangeToTheNext() {
        let meter = [
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1),
            TimeSignatureChange(numerator: 3, denominator: 4, startMeasure: 3),
        ]

        let segments = TimelineRulerSegment.segments(timeSignatureChanges: meter, tempoChanges: tempo, duration: 20)

        XCTAssertEqual(segments.map(\.startTime), [0, 4])
        XCTAssertEqual(segments.map(\.endTime), [4, 20])
        XCTAssertEqual(segments.map(\.label), ["4/4", "3/4"])
    }

    func testTempoSegmentsShowTheirTempo() {
        let tempo = [TempoChange(startMeasure: 1, bpm: 120), TempoChange(startMeasure: 3, bpm: 60)]
        let meter = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]

        let segments = TimelineRulerSegment.segments(tempoChanges: tempo, timeSignatureChanges: meter, duration: 30)

        XCTAssertEqual(segments.map(\.startTime), [0, 4])
        XCTAssertEqual(segments.map(\.endTime), [4, 30])
        XCTAssertEqual(segments.map(\.label), ["120", "60"])
    }
}
