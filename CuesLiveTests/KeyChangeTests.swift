import XCTest
@testable import CuesLive

final class KeyChangeTests: XCTestCase {
    func testDisplayedKeyWrapsSemitones() {
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "Bb", transposeSemitones: 2), "C")
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "C", transposeSemitones: -1), "B")
        XCTAssertNil(SongMusicalKey.display(baseRaw: nil, transposeSemitones: 3))
        XCTAssertEqual(SongMusicalKey.transportText(baseRaw: nil, transposeSemitones: 2), "—")
    }

    func testDefaultSelectionLeavesUtilityTracksOff() {
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Kick", groupName: "Drums"))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Shaker", groupName: "Percussion"))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Click", groupName: "Click"))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Click", groupName: nil))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "LTC", groupName: "Timecode"))
        XCTAssertTrue(KeyChangeTrackSelection.includesByDefault(displayName: "Bass", groupName: "Bass"))
        XCTAssertTrue(KeyChangeTrackSelection.includesByDefault(displayName: "Vocal", groupName: nil))
    }

    func testOldMetadataDecodesWithoutTranspose() throws {
        let json = """
        {"baseKeyRaw":"G","smartGuideEnabled":false}
        """.data(using: .utf8)!
        let metadata = try JSONDecoder().decode(SongProjectMetadata.self, from: json)
        XCTAssertEqual(metadata.transposeSemitones, 0)
        XCTAssertEqual(metadata.baseKeyRaw, "G")
    }
}
