import XCTest
@testable import CuesLive

final class ScreenPresenceTests: XCTestCase {
    /// The launch order that cancelled the first song's load: a second copy appears
    /// before the first one disappears. Neither should trigger setup or teardown again.
    func testOverlappingCopiesSetUpOnceAndNeverTearDown() {
        var presence = ScreenPresence()

        XCTAssertTrue(presence.appear())
        XCTAssertFalse(presence.appear())
        XCTAssertFalse(presence.disappear())
        XCTAssertEqual(presence.visibleCount, 1)
    }

    func testLastDisappearanceTearsDownAndNextAppearanceSetsUpAgain() {
        var presence = ScreenPresence()

        XCTAssertTrue(presence.appear())
        XCTAssertTrue(presence.disappear())
        XCTAssertTrue(presence.appear())
    }

    func testUnmatchedDisappearanceDoesNotGoNegative() {
        var presence = ScreenPresence()

        XCTAssertTrue(presence.disappear())
        XCTAssertEqual(presence.visibleCount, 0)
        XCTAssertTrue(presence.appear())
    }
}
