import SwiftData
import XCTest
@testable import CuesLive

@MainActor
final class SongTests: XCTestCase {
    func testSortedTracksFollowSortOrder() throws {
        let container = try ModelContainer(
            for: Schema(PersistenceController.modelTypes),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let song = Song(name: "Order")
        context.insert(song)
        song.tracks = [
            AudioTrack(displayName: "Keys", relativeFilePath: "keys.wav", sortOrder: 2),
            AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0),
            AudioTrack(displayName: "Bass", relativeFilePath: "bass.wav", sortOrder: 1),
        ]
        song.midiTracks = [
            MIDITrack(displayName: "Lights", sortOrder: 1),
            MIDITrack(displayName: "Patches", sortOrder: 0),
        ]

        XCTAssertEqual(song.sortedTracks.map(\.displayName), ["Kick", "Bass", "Keys"])
        XCTAssertEqual(song.sortedMIDITracks.map(\.displayName), ["Patches", "Lights"])
    }
}
