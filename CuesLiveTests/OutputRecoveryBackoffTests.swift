import XCTest
@testable import CuesLive

final class OutputRecoveryBackoffTests: XCTestCase {
    func testFirstAttemptWaitsForTheSystemToSettle() {
        XCTAssertEqual(OutputRecoveryBackoff.delay(beforeAttempt: 0), 0.5)
    }

    func testDelayDoublesThenCaps() {
        XCTAssertEqual(OutputRecoveryBackoff.delay(beforeAttempt: 1), 1)
        XCTAssertEqual(OutputRecoveryBackoff.delay(beforeAttempt: 2), 2)
        XCTAssertEqual(OutputRecoveryBackoff.delay(beforeAttempt: 3), 2)
    }

    func testDelayStaysCappedForHugeAttemptCounts() {
        XCTAssertEqual(OutputRecoveryBackoff.delay(beforeAttempt: 10_000), OutputRecoveryBackoff.maximumDelay)
    }

    func testNegativeAttemptIsTreatedAsFirst() {
        XCTAssertEqual(OutputRecoveryBackoff.delay(beforeAttempt: -3), 0.5)
    }
}
