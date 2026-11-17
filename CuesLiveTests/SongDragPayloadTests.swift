import XCTest
@testable import CuesLive

final class SongDragPayloadTests: XCTestCase {
    func testRoundTripsMultipleSongsInOrder() {
        let ids = [UUID(), UUID(), UUID()]
        XCTAssertEqual(SongDragPayload.songIDs(from: SongDragPayload.string(for: ids)), ids)
    }

    func testReadsSingleSongPayload() {
        let id = UUID()
        XCTAssertEqual(SongDragPayload.songIDs(from: "cueslive-song:\(id.uuidString)"), [id])
    }

    func testIgnoresUnrelatedText() {
        XCTAssertEqual(SongDragPayload.songIDs(from: UUID().uuidString), [])
        XCTAssertEqual(SongDragPayload.songIDs(from: "cueslive-song:not-a-uuid"), [])
    }

    func testLoadsSongsFromItemProviders() async {
        let first = [UUID(), UUID()]
        let second = [UUID()]
        let providers = [
            NSItemProvider(object: SongDragPayload.string(for: first) as NSString),
            NSItemProvider(object: "plain text" as NSString),
            NSItemProvider(object: SongDragPayload.string(for: second) as NSString),
        ]
        let ids = await SongDragPayload.songIDs(from: providers)
        XCTAssertEqual(ids, first + second)
    }
}
