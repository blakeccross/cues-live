import XCTest
@testable import CuesLive

final class SongMusicalKeyTests: XCTestCase {
    func testDisplayReturnsTheSelectedKey() {
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "Bb"), "Bb")
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "C"), "C")
        XCTAssertNil(SongMusicalKey.display(baseRaw: nil))
        XCTAssertNil(SongMusicalKey.display(baseRaw: "H"))
    }

    func testTransportTextUsesEmDashWhenUnset() {
        XCTAssertEqual(SongMusicalKey.transportText(baseRaw: nil), "—")
        XCTAssertEqual(SongMusicalKey.transportText(baseRaw: "G"), "G")
    }
}
