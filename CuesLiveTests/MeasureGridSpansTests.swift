import XCTest
@testable import CuesLive

final class MeasureGridSpansTests: XCTestCase {
    func testMeasureLinesStopAtClipHeaders() {
        let headers = [CGRect(x: 10, y: 0, width: 80, height: 16), CGRect(x: 40, y: 104, width: 30, height: 16)]
        let gaps = MeasureGridSpans.gaps(at: 50, in: headers)
        XCTAssertEqual(
            MeasureGridSpans.verticalSegments(from: 0, to: 208, skipping: gaps).map { [$0.0, $0.1] },
            [[16, 104], [120, 208]]
        )
        XCTAssertEqual(
            MeasureGridSpans.verticalSegments(from: 0, to: 208, skipping: MeasureGridSpans.gaps(at: 5, in: headers)).map { [$0.0, $0.1] },
            [[0, 208]]
        )
    }

    func testMeasureLinesIgnoreHeadersOutsideTheDrawnSpan() {
        // A redraw of only the lower lane must not trip on the upper lane's header.
        let gaps = [CGFloat(0)...16, 104...120]
        XCTAssertEqual(
            MeasureGridSpans.verticalSegments(from: 60, to: 100, skipping: gaps).map { [$0.0, $0.1] },
            [[60, 100]]
        )
    }
}
