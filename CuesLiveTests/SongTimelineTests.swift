import XCTest
@testable import CuesLive

final class SongTimelineTests: XCTestCase {
    private let intro = ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0)
    private let verse = ArrangementMarker(name: "Verse", startSeconds: 10, sortOrder: 1)
    private let chorus = ArrangementMarker(name: "Chorus", startSeconds: 20, sortOrder: 2)
    private let songEnd: TimeInterval = 30
    private let minimum = SongTimeline.minimumSectionLength

    private func makeTimeline() -> SongTimeline {
        SongTimeline(markers: [intro, verse, chorus])
    }

    private func spans(_ timeline: SongTimeline) -> [[TimeInterval]] {
        timeline.sections(songEnd: songEnd).map { [$0.timelineStartSeconds, $0.timelineEndSeconds] }
    }

    // MARK: - Deriving sections

    func testExplicitEndLeavesGapBeforeNextMarker() {
        var timeline = makeTimeline()
        timeline.markers[1].endSeconds = 15

        XCTAssertEqual(spans(timeline), [[0, 10], [10, 15], [20, 30]])
    }

    func testExplicitEndNeverRunsPastNextMarker() {
        var timeline = makeTimeline()
        timeline.markers[1].endSeconds = 25

        XCTAssertEqual(spans(timeline), [[0, 10], [10, 20], [20, 30]])
    }

    func testMarkerEndRoundTrips() throws {
        let marker = ArrangementMarker(name: "Verse", startSeconds: 10, endSeconds: 15)

        let decoded = try JSONDecoder().decode(ArrangementMarker.self, from: JSONEncoder().encode(marker))

        XCTAssertEqual(decoded, marker)
    }

    // MARK: - Linked start edits

    func testLinkedStartMoveAlsoMovesPreviousEnd() {
        var timeline = makeTimeline()

        XCTAssertTrue(timeline.apply(.start(sectionID: verse.id, time: 12, independent: false), songEnd: songEnd))

        XCTAssertEqual(spans(timeline), [[0, 12], [12, 20], [20, 30]])
    }

    func testLinkedStartMoveIsClampedInsideNeighbours() {
        var timeline = makeTimeline()

        timeline.apply(.start(sectionID: verse.id, time: 25, independent: false), songEnd: songEnd)
        XCTAssertEqual(spans(timeline)[1][0], 20 - minimum, accuracy: 0.000_1)

        timeline.apply(.start(sectionID: verse.id, time: -5, independent: false), songEnd: songEnd)
        XCTAssertEqual(spans(timeline)[1][0], minimum, accuracy: 0.000_1)
    }

    // MARK: - Independent edits

    func testIndependentStartMoveKeepsPreviousSectionInPlace() {
        var timeline = makeTimeline()

        timeline.apply(.start(sectionID: verse.id, time: 13, independent: true), songEnd: songEnd)

        XCTAssertEqual(spans(timeline), [[0, 10], [13, 20], [20, 30]])
    }

    func testIndependentStartCannotOverlapPreviousSection() {
        var timeline = makeTimeline()

        XCTAssertFalse(timeline.apply(.start(sectionID: verse.id, time: 5, independent: true), songEnd: songEnd))
        XCTAssertEqual(spans(timeline), [[0, 10], [10, 20], [20, 30]])
    }

    func testEndMoveLeavesNextMarkerInPlace() {
        var timeline = makeTimeline()

        XCTAssertTrue(timeline.apply(.end(sectionID: verse.id, time: 16), songEnd: songEnd))

        XCTAssertEqual(spans(timeline), [[0, 10], [10, 16], [20, 30]])
    }

    func testEndMoveIsClampedToNextMarkerAndClearsExplicitEnd() {
        var timeline = makeTimeline()
        timeline.apply(.end(sectionID: verse.id, time: 16), songEnd: songEnd)

        timeline.apply(.end(sectionID: verse.id, time: 28), songEnd: songEnd)

        XCTAssertEqual(spans(timeline), [[0, 10], [10, 20], [20, 30]])
        XCTAssertNil(timeline.markers[1].endSeconds)
    }

    func testEndMoveKeepsMinimumLength() {
        var timeline = makeTimeline()

        timeline.apply(.end(sectionID: verse.id, time: 2), songEnd: songEnd)

        XCTAssertEqual(spans(timeline)[1][1], 10 + minimum, accuracy: 0.000_1)
    }

    func testLastSectionEndStaysBeforeSongEnd() {
        var timeline = makeTimeline()

        timeline.apply(.end(sectionID: chorus.id, time: 26), songEnd: songEnd)
        XCTAssertEqual(spans(timeline).last, [20, 26])

        timeline.apply(.end(sectionID: chorus.id, time: 40), songEnd: songEnd)
        XCTAssertEqual(spans(timeline).last, [20, 30])
    }

    func testStartMoveIntoGapStaysAfterPreviousEnd() {
        var timeline = makeTimeline()
        timeline.apply(.end(sectionID: verse.id, time: 15), songEnd: songEnd)

        timeline.apply(.start(sectionID: chorus.id, time: 12, independent: false), songEnd: songEnd)

        XCTAssertEqual(spans(timeline), [[0, 10], [10, 15], [15, 30]])
    }

    func testUnchangedOrMissingSectionReportsNoEdit() {
        var timeline = makeTimeline()

        XCTAssertFalse(timeline.apply(.start(sectionID: verse.id, time: 10, independent: false), songEnd: songEnd))
        XCTAssertFalse(timeline.apply(.end(sectionID: verse.id, time: 20), songEnd: songEnd))
        XCTAssertFalse(timeline.apply(.end(sectionID: UUID(), time: 5), songEnd: songEnd))
        XCTAssertEqual(timeline, makeTimeline())
    }
}
