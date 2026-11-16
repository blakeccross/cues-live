import XCTest
@testable import CuesLive

final class OverlapTransitionTimingTests: XCTestCase {
    func testWindowEndsAtTheOutPoint() {
        XCTAssertEqual(
            OverlapTransitionTiming.outgoingWindowStart(outgoingDuration: 90, windowDuration: 10, outgoingStart: 4),
            80
        )
    }

    func testWindowNeverStartsBeforeTheInPoint() {
        XCTAssertEqual(
            OverlapTransitionTiming.outgoingWindowStart(outgoingDuration: 12, windowDuration: 10, outgoingStart: 6),
            6
        )
    }

    func testStartOffsetCannotReachBeforeTheInPoint() {
        let offset = OverlapTransitionTiming.clampedStartOffset(
            9,
            windowDuration: 10,
            outgoingDuration: 12,
            outgoingStart: 6
        )

        XCTAssertEqual(offset, 6)
    }

    func testDefaultOffsetFitsAShortPlayedLength() {
        let offset = OverlapTransitionTiming.defaultStartOffset(
            windowDuration: 10,
            outgoingDuration: 12,
            outgoingStart: 9
        )

        XCTAssertEqual(offset, 3)
    }

    func testIncomingLaneOffsetRoundTripsThroughTheStartOffset() {
        let laneOffset = OverlapTransitionTiming.incomingLaneOffset(
            outgoingDuration: 14,
            windowDuration: 10,
            startOffsetSeconds: 3,
            outgoingStart: 6
        )
        XCTAssertEqual(laneOffset, 5, "The window runs 6–14 and the incoming song starts at 11.")

        let offset = OverlapTransitionTiming.startOffset(
            outgoingDuration: 14,
            windowDuration: 10,
            incomingLaneOffset: laneOffset,
            outgoingStart: 6
        )
        XCTAssertEqual(offset, 3)
    }

    func testSongsWithoutAnInPointKeepTheirPlacement() {
        XCTAssertEqual(
            OverlapTransitionTiming.incomingLaneOffset(outgoingDuration: 60, windowDuration: 10, startOffsetSeconds: 5),
            5
        )
    }
}
