import XCTest
@testable import CuesLive

final class OverlapEditorTimelineTests: XCTestCase {
    /// Outgoing plays 10–70 (60 s), incoming 2–42 (40 s), overlapping by 8 s.
    private func makeTimeline(offset: TimeInterval = 8) -> OverlapEditorTimeline {
        OverlapEditorTimeline(outgoingRange: 10...70, incomingRange: 2...42, startOffsetSeconds: offset)
    }

    func testIncomingEntersOffsetBeforeTheOutgoingOutPoint() {
        let timeline = makeTimeline()

        XCTAssertEqual(timeline.incomingEntry, 52)
        XCTAssertEqual(timeline.duration, 92)
        XCTAssertEqual(timeline.transitionCenter, 56)
    }

    func testSongTimesMapThroughTheirInPoints() {
        let timeline = makeTimeline()

        XCTAssertEqual(timeline.outgoingTime(at: 0), 10)
        XCTAssertEqual(timeline.outgoingTime(at: 55), 65)
        XCTAssertNil(timeline.outgoingTime(at: 60))
        XCTAssertNil(timeline.incomingTime(at: 51))
        XCTAssertEqual(timeline.incomingTime(at: 55), 5)
    }

    func testEditorTimeRoundTripsThroughEachSong() {
        let timeline = makeTimeline()

        XCTAssertEqual(timeline.editorTime(outgoingTime: 65), 55)
        XCTAssertEqual(timeline.editorTime(incomingTime: 5), 55)
    }

    func testStartOffsetRoundTripsThroughTheEntry() {
        let timeline = makeTimeline()

        XCTAssertEqual(timeline.startOffset(incomingEntry: timeline.incomingEntry), 8)
        XCTAssertEqual(timeline.startOffset(incomingEntry: 45), 15)
    }

    func testOffsetNeverExceedsEitherSong() {
        XCTAssertEqual(makeTimeline(offset: 50).startOffsetSeconds, 40, "The incoming song is only 40 s long.")
        XCTAssertEqual(makeTimeline().startOffset(incomingEntry: -5), 40)
        XCTAssertEqual(makeTimeline().startOffset(incomingEntry: 80), 0)
    }

    func testOffsetLongerThanTheOldEditorWindowIsKept() {
        XCTAssertEqual(makeTimeline(offset: 25).startOffsetSeconds, 25)
    }

    func testFocusRangeSurroundsTheOverlap() {
        XCTAssertEqual(makeTimeline().focusRange(margin: 10), 42...70)
    }

    func testFocusRangeStaysWithinTheSongs() {
        let timeline = OverlapEditorTimeline(outgoingRange: 0...6, incomingRange: 0...3, startOffsetSeconds: 2)

        XCTAssertEqual(timeline.focusRange(margin: 10), 0...7, "Starts at the outgoing in point and ends with the incoming song.")
    }
}
