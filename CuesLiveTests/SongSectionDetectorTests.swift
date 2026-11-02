import XCTest
@testable import CuesLive

final class SongSectionDetectorTests: XCTestCase {
    func testFirstSectionIsPinnedToZero() {
        let markers = SongSectionDetector.markers(fromSectionStarts: [4.2, 30, 60], songDuration: 120)

        XCTAssertEqual(markers.map(\.startSeconds), [0, 4.2, 30, 60])
        XCTAssertEqual(markers.map(\.name), ["Section 1", "Section 2", "Section 3", "Section 4"])
        XCTAssertEqual(markers.map(\.sortOrder), [0, 1, 2, 3])
    }

    func testStartAtZeroIsNotDuplicated() {
        let markers = SongSectionDetector.markers(fromSectionStarts: [0, 30], songDuration: 90)

        XCTAssertEqual(markers.map(\.startSeconds), [0, 30])
    }

    func testUnsortedAndOutOfRangeStartsAreCleaned() {
        let markers = SongSectionDetector.markers(
            fromSectionStarts: [60, -3, 30, 500],
            songDuration: 120
        )

        XCTAssertEqual(markers.map(\.startSeconds), [0, 30, 60])
    }

    func testSectionsShorterThanMinimumAreMerged() {
        let markers = SongSectionDetector.markers(fromSectionStarts: [0.4, 30, 30.5], songDuration: 120)

        XCTAssertEqual(markers.map(\.startSeconds), [0, 30])
    }

    func testShortTailIsFoldedIntoPreviousSection() {
        let markers = SongSectionDetector.markers(fromSectionStarts: [30, 119.5], songDuration: 120)

        XCTAssertEqual(markers.map(\.startSeconds), [0, 30])
    }

    func testNoStartsYieldsSingleSection() {
        let markers = SongSectionDetector.markers(fromSectionStarts: [], songDuration: 120)

        XCTAssertEqual(markers.map(\.startSeconds), [0])
    }
}
