import XCTest
@testable import CuesLive

final class OutputSampleRateTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "OutputSampleRateTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToFortyEightKilohertz() {
        XCTAssertEqual(OutputSampleRate.selected(in: defaults), 48_000)
    }

    func testRemembersTheChosenRate() {
        OutputSampleRate.select(44_100, in: defaults)

        XCTAssertEqual(OutputSampleRate.selected(in: defaults), 44_100)
    }

    func testIgnoresRatesThatAreNotOffered() {
        OutputSampleRate.select(96_000, in: defaults)
        OutputSampleRate.select(12_345, in: defaults)

        XCTAssertEqual(OutputSampleRate.selected(in: defaults), 96_000)
    }

    func testFallsBackToTheDefaultForAStoredRateThatIsNoLongerOffered() {
        defaults.set(22_050.0, forKey: OutputSampleRate.storageKey)

        XCTAssertEqual(OutputSampleRate.selected(in: defaults), 48_000)
    }

    func testLabelsUseKilohertz() {
        XCTAssertEqual(OutputSampleRate.choices.map(OutputSampleRate.label(for:)), ["44.1 kHz", "48 kHz", "88.2 kHz", "96 kHz"])
    }
}
