import XCTest
@testable import CuesLive

final class WaveformMinMaxTests: XCTestCase {
    func testOverviewKeepsEachColumnAsABlock() {
        let series = WaveformMinMax(mins: [-0.1, -0.5, -0.2, -0.9], maxes: [0.2, 0.4, 0.8, 0.1])
        let overview = series.overview()
        let block = Double(WaveformOverview.block)

        XCTAssertEqual(overview.sampleCount, 4 * WaveformOverview.block)
        let columns = overview.columns(start: 0, step: block, count: 4)
        XCTAssertEqual(columns[1]?.0, -0.5)
        XCTAssertEqual(columns[2]?.1, 0.8)
    }

    func testOverviewColumnsSpanningSeveralBlocksKeepTheirExtremes() {
        let series = WaveformMinMax(mins: [-0.1, -0.5, -0.2, -0.9], maxes: [0.2, 0.4, 0.8, 0.1])
        let block = Double(WaveformOverview.block)

        let columns = series.overview().columns(start: 0, step: 2 * block - 1, count: 2)

        XCTAssertEqual(columns[0]?.0, -0.5)
        XCTAssertEqual(columns[0]?.1, 0.4)
        XCTAssertEqual(columns[1]?.0, -0.9)
        XCTAssertEqual(columns[1]?.1, 0.8)
    }

    func testEmptySeriesHasNoColumns() {
        let columns = WaveformMinMax.empty.overview().columns(start: 0, step: 1, count: 3)
        XCTAssertEqual(columns.count, 3)
        XCTAssertTrue(columns.allSatisfy { $0 == nil })
    }
}
