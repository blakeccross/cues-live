import XCTest
@testable import CuesLive

final class PeakMeterHolderTests: XCTestCase {
    func testConsumeShowsTheHighestReportedPeak() {
        let meter = PeakMeterHolder()

        meter.report(0.25)
        meter.report(0.75)
        meter.report(0.5)

        XCTAssertEqual(meter.consume(), 0.75)
    }

    func testReportIgnoresSilenceAndInvalidLevels() {
        let meter = PeakMeterHolder()

        meter.report(0)
        meter.report(-1)
        meter.report(.nan)
        meter.report(.infinity)

        XCTAssertEqual(meter.consume(), 0)
    }

    func testHeldPeakDecaysBetweenReads() {
        let meter = PeakMeterHolder()
        meter.report(1)
        XCTAssertEqual(meter.consume(), 1)

        Thread.sleep(forTimeInterval: 0.05)
        _ = meter.consume()
        let afterDecay = meter.consume()

        XCTAssertLessThan(afterDecay, 1)
        XCTAssertGreaterThan(afterDecay, 0)
    }

    func testResetClearsThePeak() {
        let meter = PeakMeterHolder()
        meter.report(0.5)

        meter.reset()

        XCTAssertEqual(meter.consume(), 0)
    }
}
