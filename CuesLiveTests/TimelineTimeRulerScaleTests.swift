import XCTest
@testable import CuesLive

final class TimelineTimeRulerScaleTests: XCTestCase {
    func testLabelsMillisecondsAtTheDeepestZoom() {
        let scale = TimelineTimeRulerScale(pixelsPerSecond: TimelineLayout.basePixelsPerSecond * TimelineLayout.maxZoom)

        XCTAssertEqual(scale.major, 0.002)
        XCTAssertEqual(scale.label(for: 131.546), "2:11.546")
    }

    func testLabelsWholeSecondsWhenZoomedOut() {
        let scale = TimelineTimeRulerScale(pixelsPerSecond: 6)

        XCTAssertEqual(scale.label(for: 125), "2:05")
    }
}
