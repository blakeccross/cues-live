import XCTest
@testable import CuesLive

final class SongBakeFingerprintTests: XCTestCase {
    func testFingerprintChangesWhenTrackVolumeChanges() {
        let song = Song(name: "Bake Test")
        let track = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        track.volume = 1.0
        song.tracks = [track]

        let projectState = SongProjectBridge.ProjectState(
            timeline: SongTimeline(),
            tempoChanges: SongProjectBridge.defaultTempoChanges(for: song),
            timeSignatureChanges: SongProjectBridge.defaultTimeSignatureChanges(for: song),
            midiEvents: []
        )

        let initial = SongBakeFingerprint.compute(for: song, projectState: projectState)
        track.volume = 0.5
        let changed = SongBakeFingerprint.compute(for: song, projectState: projectState)

        XCTAssertNotEqual(initial, changed)
    }

    func testBakedTrackIDIsStableForSongAndGroup() {
        let songID = UUID()
        let groupID = UUID()

        let first = SongBakeStore.bakedGroupTrackID(songID: songID, groupID: groupID)
        let second = SongBakeStore.bakedGroupTrackID(songID: songID, groupID: groupID)

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            SongBakeStore.bakedGroupTrackID(songID: songID, groupID: groupID),
            SongBakeStore.bakedGroupTrackID(songID: songID, groupID: nil)
        )
    }
}
