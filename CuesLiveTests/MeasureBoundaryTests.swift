import XCTest
@testable import CuesLive

final class MeasureBoundaryTests: XCTestCase {
    func testGridDetailAppearsAsTheBeatGrowsPastSevenPoints() {
        // 120 BPM is a 0.5 s quarter. A level stays hidden until its steps are more than 7 points apart.
        let hidden = MeasureTiming.LaneGridDetail.detail(pixelsPerSecond: 10, fastestBPM: 120)
        XCTAssertFalse(hidden.showsBeats)
        XCTAssertFalse(hidden.showsSubdivisions)

        let beatsOnly = MeasureTiming.LaneGridDetail.detail(pixelsPerSecond: 16, fastestBPM: 120)
        XCTAssertTrue(beatsOnly.showsBeats)
        XCTAssertFalse(beatsOnly.showsSubdivisions)

        let withEighths = MeasureTiming.LaneGridDetail.detail(pixelsPerSecond: 30, fastestBPM: 120)
        XCTAssertTrue(withEighths.showsBeats)
        XCTAssertTrue(withEighths.showsSubdivisions)
    }

    func testBeatGridPlacesQuartersAndEighths() {
        // 120 BPM in 4/4 is a 0.5 s beat. Downbeats stay out of both lists.
        let grid = MeasureTiming.beatGridTimes(
            duration: 4,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: []
        )
        XCTAssertEqual(grid.beats, [0.5, 1, 1.5, 2.5, 3, 3.5])
        XCTAssertEqual(grid.subdivisions, [0.25, 0.75, 1.25, 1.75, 2.25, 2.75, 3.25, 3.75])
    }

    func testBoundariesFollowTempoMapAtEveryMeasureWhenSpacious() {
        // 120 BPM in 4/4 is 2 s per measure; a wide lane keeps every measure.
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: 20,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            contentWidth: 20_000,
            timeSignatureChanges: []
        )
        XCTAssertEqual(boundaries, [2, 4, 6, 8, 10, 12, 14, 16, 18])
    }

    func testBoundariesRespectTempoChange() {
        // Measures 1-2 at 120 BPM (2 s each), then 60 BPM (4 s each).
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: 14,
            tempoChanges: [
                TempoChange(startMeasure: 1, bpm: 120),
                TempoChange(startMeasure: 3, bpm: 60),
            ],
            contentWidth: 14_000,
            timeSignatureChanges: []
        )
        XCTAssertEqual(boundaries, [2, 4, 8, 12])
    }

    func testVisibleRangeLimitsBoundaries() {
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: 3_600,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            contentWidth: 36_000,
            timeSignatureChanges: [],
            visibleTimeRange: 1_000...1_050
        )
        XCTAssertFalse(boundaries.isEmpty)
        XCTAssertLessThan(boundaries.count, 100)
        XCTAssertTrue(boundaries.allSatisfy { $0 >= 1_000 - 2 && $0 <= 1_050 + 2 })
    }

    func testZeroTempoDoesNotHangOrEmitBoundaries() {
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: 300,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 0)],
            contentWidth: 3_000,
            timeSignatureChanges: []
        )
        XCTAssertTrue(boundaries.isEmpty)
    }

    func testLongSongBoundariesStayWithinVisibleWindow() {
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: 3 * 3_600,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 140)],
            contentWidth: 60_000,
            timeSignatureChanges: [],
            visibleTimeRange: 9_000...9_100
        )
        XCTAssertFalse(boundaries.isEmpty)
        XCTAssertLessThan(boundaries.count, 100)
        XCTAssertEqual(boundaries, boundaries.sorted())
    }

    func testActiveChangeIgnoresInputOrder() {
        let tempos = [
            TempoChange(startMeasure: 9, bpm: 90),
            TempoChange(startMeasure: 1, bpm: 120),
            TempoChange(startMeasure: 5, bpm: 60),
        ]
        XCTAssertEqual(tempos.active(atMeasure: 1)?.bpm, 120)
        XCTAssertEqual(tempos.active(atMeasure: 4)?.bpm, 120)
        XCTAssertEqual(tempos.active(atMeasure: 5)?.bpm, 60)
        XCTAssertEqual(tempos.active(atMeasure: 100)?.bpm, 90)
    }

    func testActiveChangeFallsBackToEarliestBeforeFirstStart() {
        let signatures = [
            TimeSignatureChange(numerator: 7, denominator: 8, startMeasure: 4),
            TimeSignatureChange(numerator: 3, denominator: 4, startMeasure: 2),
        ]
        XCTAssertEqual(signatures.active(atMeasure: 1)?.numerator, 3)
    }

    func testActiveChangeBreaksTiesBySortOrder() {
        let tempos = [
            TempoChange(startMeasure: 1, bpm: 100, sortOrder: 1),
            TempoChange(startMeasure: 1, bpm: 110, sortOrder: 0),
        ]
        XCTAssertEqual(tempos.active(atMeasure: 1)?.bpm, 100)
    }

    func testActiveChangeOfEmptyArrayIsNil() {
        XCTAssertNil([TempoChange]().active(atMeasure: 1))
    }
}
