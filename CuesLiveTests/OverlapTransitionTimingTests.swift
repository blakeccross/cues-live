import XCTest
@testable import CuesLive

final class OverlapTransitionTimingTests: XCTestCase {
    func testDefaultOffsetFitsAShortPlayedLength() {
        let offset = OverlapTransitionTiming.defaultStartOffset(
            windowDuration: 10,
            outgoingDuration: 12,
            outgoingStart: 9
        )

        XCTAssertEqual(offset, 3)
    }

    func testDefaultOffsetIsFiveSecondsForALongSong() {
        XCTAssertEqual(
            OverlapTransitionTiming.defaultStartOffset(windowDuration: 10, outgoingDuration: 200),
            5
        )
    }
}
