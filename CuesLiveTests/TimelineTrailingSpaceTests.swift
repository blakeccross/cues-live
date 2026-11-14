import XCTest
@testable import CuesLive

final class TimelineTrailingSpaceTests: XCTestCase {
    // 120 BPM in 4/4 is a 2 s measure.
    private let tempos = [TempoChange(startMeasure: 1, bpm: 120)]
    private let fourFour = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]

    private func displayDuration(measures: Double) -> TimeInterval {
        TimelineTrailingSpace.displayDuration(
            songDuration: measures * 2,
            tempoChanges: tempos,
            timeSignatureChanges: fourFour
        )
    }

    func testAddsTenPercentOfTheSongsMeasures() {
        XCTAssertEqual(displayDuration(measures: 100), 110 * 2, accuracy: 0.001)
    }

    func testPaddingShrinksWhenTheSongIsTrimmed() {
        XCTAssertEqual(displayDuration(measures: 90), 99 * 2, accuracy: 0.001)
    }

    func testPartialMeasuresCountAsWholeAndPaddingRoundsUp() {
        // 95.5 measures touches 96 measures; 9.6 rounds up to 10.
        XCTAssertEqual(displayDuration(measures: 95.5), 106 * 2, accuracy: 0.001)
    }

    func testShortSongsShowAtLeastFiftyEightMeasures() {
        XCTAssertEqual(displayDuration(measures: 20), 58 * 2, accuracy: 0.001)
        XCTAssertEqual(displayDuration(measures: 0), 58 * 2, accuracy: 0.001)
    }

    func testPaddingFollowsTheTempoAfterTheSong() {
        // 100 measures at 120 BPM, then 60 BPM (4 s measures) from measure 101.
        let changes = tempos + [TempoChange(startMeasure: 101, bpm: 60)]
        let duration = TimelineTrailingSpace.displayDuration(
            songDuration: 200,
            tempoChanges: changes,
            timeSignatureChanges: fourFour
        )
        XCTAssertEqual(duration, 200 + 10 * 4, accuracy: 0.001)
    }
}
