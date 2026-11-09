import XCTest
@testable import CuesLive

final class LiveSetlistZoomAnchorTests: XCTestCase {
    func testZoomKeepsPlayheadAtTheSameViewportPosition() {
        let duration: TimeInterval = 100
        let playhead: TimeInterval = 10
        let before = LiveSetlistZoomAnchor.laneWidth(timelineDuration: duration, zoom: 1)
        let after = LiveSetlistZoomAnchor.laneWidth(timelineDuration: duration, zoom: 2)
        let delta = LiveSetlistZoomAnchor.scrollOffsetDelta(
            precedingLaneWidthsBefore: [before],
            currentLaneWidthBefore: before,
            precedingLaneWidthsAfter: [after],
            currentLaneWidthAfter: after,
            playheadTime: playhead,
            timelineDuration: duration
        )

        let offset: CGFloat = 80
        let viewportBefore = LiveSetlistZoomAnchor.scalablePlayheadX(
            precedingLaneWidths: [before],
            currentLaneWidth: before,
            playheadTime: playhead,
            timelineDuration: duration
        ) - offset
        let viewportAfter = LiveSetlistZoomAnchor.scalablePlayheadX(
            precedingLaneWidths: [after],
            currentLaneWidth: after,
            playheadTime: playhead,
            timelineDuration: duration
        ) - (offset + delta)

        XCTAssertEqual(before, 600, accuracy: 0.01)
        XCTAssertEqual(after, 1200, accuracy: 0.01)
        XCTAssertEqual(delta, 660, accuracy: 0.01)
        XCTAssertEqual(viewportBefore, viewportAfter, accuracy: 0.01)
    }

    func testPlayheadAtLaneStartOnlyFollowsPrecedingLaneGrowth() {
        let delta = LiveSetlistZoomAnchor.scrollOffsetDelta(
            precedingLaneWidthsBefore: [600],
            currentLaneWidthBefore: 600,
            precedingLaneWidthsAfter: [1200],
            currentLaneWidthAfter: 1200,
            playheadTime: 0,
            timelineDuration: 100
        )
        XCTAssertEqual(delta, 600, accuracy: 0.01)
    }

    func testUnchangedMinimumLaneWidthDoesNotMoveThePlayhead() {
        let narrow = LiveSetlistZoomAnchor.laneWidth(timelineDuration: 10, zoom: 1)
        let stillNarrow = LiveSetlistZoomAnchor.laneWidth(timelineDuration: 10, zoom: 2)
        XCTAssertEqual(narrow, stillNarrow, accuracy: 0.01)

        let delta = LiveSetlistZoomAnchor.scrollOffsetDelta(
            precedingLaneWidthsBefore: [],
            currentLaneWidthBefore: narrow,
            precedingLaneWidthsAfter: [],
            currentLaneWidthAfter: stillNarrow,
            playheadTime: 5,
            timelineDuration: 10
        )
        XCTAssertEqual(delta, 0, accuracy: 0.01)
    }

    func testZoomPastMinimumWidthAnchorsInsideTheLane() {
        let before = LiveSetlistZoomAnchor.laneWidth(timelineDuration: 10, zoom: 1)
        let after = LiveSetlistZoomAnchor.laneWidth(timelineDuration: 10, zoom: 8)
        let delta = LiveSetlistZoomAnchor.scrollOffsetDelta(
            precedingLaneWidthsBefore: [],
            currentLaneWidthBefore: before,
            precedingLaneWidthsAfter: [],
            currentLaneWidthAfter: after,
            playheadTime: 5,
            timelineDuration: 10
        )
        XCTAssertEqual(before, 320, accuracy: 0.01)
        XCTAssertEqual(after, 480, accuracy: 0.01)
        XCTAssertEqual(delta, 80, accuracy: 0.01)
    }

    func testPlayheadPastTheSongEndStaysAtTheLaneEnd() {
        let x = LiveSetlistZoomAnchor.scalablePlayheadX(
            precedingLaneWidths: [],
            currentLaneWidth: 600,
            playheadTime: 150,
            timelineDuration: 100
        )
        XCTAssertEqual(x, 600, accuracy: 0.01)
    }

    func testUnloadedPrecedingLaneDoesNotChangeTheZoomDelta() {
        let unloaded = LiveSetlistZoomAnchor.laneWidth(timelineDuration: nil, zoom: 1)
        XCTAssertEqual(
            unloaded,
            LiveSetlistZoomAnchor.laneWidth(timelineDuration: nil, zoom: 3),
            accuracy: 0.01
        )
        let before = LiveSetlistZoomAnchor.laneWidth(timelineDuration: 100, zoom: 1)
        let after = LiveSetlistZoomAnchor.laneWidth(timelineDuration: 100, zoom: 2)
        let delta = LiveSetlistZoomAnchor.scrollOffsetDelta(
            precedingLaneWidthsBefore: [unloaded],
            currentLaneWidthBefore: before,
            precedingLaneWidthsAfter: [unloaded],
            currentLaneWidthAfter: after,
            playheadTime: 0,
            timelineDuration: 100
        )
        XCTAssertEqual(delta, 0, accuracy: 0.01)
    }

    func testIncrementalStepsKeepThePlayheadPutWhenTimeAdvances() {
        let duration: TimeInterval = 100
        var offset: CGFloat = 40
        var zoom: CGFloat = 1
        var time: TimeInterval = 10

        func viewport(zoom: CGFloat, time: TimeInterval, offset: CGFloat) -> CGFloat {
            let width = LiveSetlistZoomAnchor.laneWidth(timelineDuration: duration, zoom: zoom)
            return LiveSetlistZoomAnchor.scalablePlayheadX(
                precedingLaneWidths: [width],
                currentLaneWidth: width,
                playheadTime: time,
                timelineDuration: duration
            ) - offset
        }

        let steps: [(zoom: CGFloat, time: TimeInterval)] = [
            (1.5, 10),
            (1.5, 12),
            (2, 12),
            (2.5, 14),
        ]
        for step in steps {
            let before = viewport(zoom: zoom, time: time, offset: offset)
            if step.time != time {
                time = step.time
                let moved = viewport(zoom: zoom, time: time, offset: offset)
                XCTAssertGreaterThan(abs(moved - before), 1)
            }
            let pinned = viewport(zoom: zoom, time: time, offset: offset)
            let widthBefore = LiveSetlistZoomAnchor.laneWidth(timelineDuration: duration, zoom: zoom)
            let widthAfter = LiveSetlistZoomAnchor.laneWidth(timelineDuration: duration, zoom: step.zoom)
            offset += LiveSetlistZoomAnchor.scrollOffsetDelta(
                precedingLaneWidthsBefore: [widthBefore],
                currentLaneWidthBefore: widthBefore,
                precedingLaneWidthsAfter: [widthAfter],
                currentLaneWidthAfter: widthAfter,
                playheadTime: time,
                timelineDuration: duration
            )
            zoom = step.zoom
            XCTAssertEqual(
                viewport(zoom: zoom, time: time, offset: offset),
                pinned,
                accuracy: 0.01
            )
        }
    }

    func testSessionAppliesTheWholeGestureFromTheOriginalOffset() {
        var session = LiveSetlistZoomScrollSession()
        let contentWidth: CGFloat = 4_000
        var actual: CGFloat = 100

        let first = session.update(
            batchID: 1,
            delta: 50,
            actualOffset: actual,
            minimumOffset: 0,
            maximumOffset: contentWidth,
            contentWidth: contentWidth,
            allowStable: false
        )
        XCTAssertEqual(first.offset, 150)
        XCTAssertFalse(first.isSettled)
        actual = 150

        let grown = session.update(
            batchID: 1,
            delta: 80,
            actualOffset: actual,
            minimumOffset: 0,
            maximumOffset: contentWidth,
            contentWidth: contentWidth,
            allowStable: false
        )
        XCTAssertEqual(grown.offset, 180)
        actual = 180

        let settled = session.update(
            batchID: 1,
            delta: 80,
            actualOffset: actual,
            minimumOffset: 0,
            maximumOffset: contentWidth,
            contentWidth: contentWidth,
            allowStable: false
        )
        XCTAssertNil(settled.offset)
        XCTAssertTrue(settled.isSettled)
    }

    func testSessionCarriesAnUnreachedTargetIntoTheNextGesture() {
        var session = LiveSetlistZoomScrollSession()
        let first = session.update(
            batchID: 1,
            delta: 500,
            actualOffset: 100,
            minimumOffset: 0,
            maximumOffset: 200,
            contentWidth: 400,
            allowStable: false
        )
        XCTAssertEqual(first.offset, 200)
        XCTAssertFalse(first.isSettled)

        let next = session.update(
            batchID: 2,
            delta: 25,
            actualOffset: 200,
            minimumOffset: 0,
            maximumOffset: 2_000,
            contentWidth: 2_400,
            allowStable: false
        )
        XCTAssertEqual(next.offset, 625)
    }
}
