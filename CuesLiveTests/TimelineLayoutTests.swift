import XCTest
@testable import CuesLive

final class TimelineLayoutTests: XCTestCase {
    func testZoomedOffsetKeepsTheAnchoredContentInPlace() {
        // Content x 1,300 sits 300 pt into the viewport; doubling the width moves it to 2,600.
        let offset = TimelineLayout.zoomedOffset(
            anchorX: 300,
            offset: 1_000,
            oldWidth: 10_000,
            newWidth: 20_000,
            viewportWidth: 800
        )

        XCTAssertEqual(offset, 2_300)
    }

    func testZoomedOffsetClampsToTheScrollableRange() {
        XCTAssertEqual(
            TimelineLayout.zoomedOffset(anchorX: 400, offset: 0, oldWidth: 10_000, newWidth: 5_000, viewportWidth: 800),
            0
        )
        XCTAssertEqual(
            TimelineLayout.zoomedOffset(anchorX: 790, offset: 9_200, oldWidth: 10_000, newWidth: 5_000, viewportWidth: 800),
            4_200
        )
    }

    func testLiveZoomStepScalesTheWidthAndKeepsTheAnchor() throws {
        // Committed at zoom 2, 10,000 pt wide; the live zoom is already 4 (20,000 pt).
        let step = try XCTUnwrap(TimelineLayout.liveZoomStep(
            from: 4,
            by: 1.5,
            range: 1...16,
            committedZoom: 2,
            committedWidth: 10_000,
            offset: 1_000,
            anchorX: 300,
            viewportWidth: 800
        ))

        XCTAssertEqual(step.zoom, 6)
        XCTAssertEqual(step.contentWidth, 30_000)
        // Content x 1,300 of 20,000 is x 1,950 of 30,000, still 300 pt into the viewport.
        XCTAssertEqual(step.offset, 1_650, accuracy: 0.001)
    }

    func testLiveZoomStepStopsAtTheRange() throws {
        let clamped = try XCTUnwrap(TimelineLayout.liveZoomStep(
            from: 12, by: 2, range: 1...16, committedZoom: 2, committedWidth: 10_000,
            offset: 0, anchorX: 0, viewportWidth: 800
        ))
        XCTAssertEqual(clamped.zoom, 16)

        XCTAssertNil(TimelineLayout.liveZoomStep(
            from: 16, by: 2, range: 1...16, committedZoom: 2, committedWidth: 10_000,
            offset: 0, anchorX: 0, viewportWidth: 800
        ), "already at the maximum")
    }
}
