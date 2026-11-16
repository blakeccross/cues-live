import XCTest
@testable import CuesLive

final class ClickSchedulerTests: XCTestCase {
    func testFourFourAt120BPMSchedulesQuarterNoteClicksInWindow() {
        let tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        let timeSignatures = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]

        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: 2,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatures,
            rhythm: .quarter
        )

        XCTAssertEqual(clicks.count, 4)
        XCTAssertEqual(clicks[0].time, 0, accuracy: 0.001)
        XCTAssertTrue(clicks[0].isAccent)
        XCTAssertEqual(clicks[1].time, 0.5, accuracy: 0.001)
        XCTAssertFalse(clicks[1].isAccent)
        XCTAssertEqual(clicks[2].time, 1.0, accuracy: 0.001)
        XCTAssertEqual(clicks[3].time, 1.5, accuracy: 0.001)
    }

    func testEighthNoteSubdivisionDoublesClickDensity() {
        let tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        let timeSignatures = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]

        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: 1,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatures,
            rhythm: .eighth
        )

        XCTAssertEqual(clicks.count, 4)
        XCTAssertEqual(clicks[0].time, 0, accuracy: 0.001)
        XCTAssertEqual(clicks[1].time, 0.25, accuracy: 0.001)
        XCTAssertEqual(clicks[2].time, 0.5, accuracy: 0.001)
        XCTAssertEqual(clicks[3].time, 0.75, accuracy: 0.001)
    }

    func testWindowStartsMidMeasure() {
        let tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        let timeSignatures = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]

        let clicks = ClickScheduler.scheduledClicks(
            from: 0.75,
            to: 1.51,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatures,
            rhythm: .quarter
        )

        XCTAssertEqual(clicks.count, 2)
        XCTAssertEqual(clicks[0].time, 1.0, accuracy: 0.001)
        XCTAssertEqual(clicks[1].time, 1.5, accuracy: 0.001)
    }

    func testAutoClicksEighthsInSixEight() {
        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: 1.5,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 6, denominator: 8, startMeasure: 1)],
            rhythm: .auto
        )

        XCTAssertEqual(clicks.count, 6)
        XCTAssertEqual(clicks[1].time, 0.25, accuracy: 0.001)
        XCTAssertEqual(clicks.map(\.isAccent), [true, false, false, false, false, false])
    }

    func testAutoClicksQuartersInFourFour() {
        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: 2,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)],
            rhythm: .auto
        )

        XCTAssertEqual(clicks.map(\.time), [0, 0.5, 1.0, 1.5])
    }

    func testAutoCountsEverySevenEightBeatAndAccentsEachBar() {
        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: 3.5,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 7, denominator: 8, startMeasure: 1)],
            rhythm: .auto
        )

        XCTAssertEqual(clicks.count, 14)
        XCTAssertTrue(clicks[7].isAccent)
        XCTAssertEqual(clicks[7].time, 1.75, accuracy: 0.001)
    }

    func testEighthTripletsPlaceThreeClicksPerBeat() {
        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: 0.5,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)],
            rhythm: .eighthTriplet
        )

        XCTAssertEqual(clicks.count, 3)
        XCTAssertEqual(clicks[1].time, 0.5 / 3, accuracy: 0.001)
    }

    func testHalfNotesClickTwicePerFourFourBar() {
        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: 2,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)],
            rhythm: .half
        )

        XCTAssertEqual(clicks.map(\.time), [0, 1.0])
    }
}
