import SwiftData
import XCTest
@testable import CuesLive

final class SongEditSnapshotTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testCaptureApplyRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let song = Song(name: "Undo Test")
        song.bpm = 128
        song.baseKeyRaw = "Bb"
        song.transposeSemitones = 2

        let track = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        track.volume = 0.5
        track.isMuted = true
        track.trimStartSeconds = 1.5
        track.trimEndSeconds = 10.0
        track.song = song
        song.tracks = [track]
        context.insert(song)

        var timeline = SongTimeline(
            markers: [ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0, loops: true)],
            clips: [TrackClip(trackID: track.id, timelineStartSeconds: 0, duration: 8.5, sourceStartSeconds: 1.5)]
        )
        var tempoChanges = [TempoChange(startMeasure: 1, bpm: 128)]
        var timeSignatureChanges = [
            TimeSignatureChange(numerator: 3, denominator: 4, startMeasure: 1, sortOrder: 0)
        ]
        var midiEvents: [MIDIEvent] = []

        let snapshot = SongEditSnapshot.capture(
            song: song,
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents
        )

        song.bpm = 90
        song.baseKeyRaw = "G"
        song.transposeSemitones = -1
        track.volume = 1.0
        track.isMuted = false
        timeline = SongTimeline()
        tempoChanges = [TempoChange(startMeasure: 1, bpm: 90)]
        timeSignatureChanges = [
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0)
        ]

        timeline = snapshot.timeline
        tempoChanges = snapshot.tempoChanges
        timeSignatureChanges = snapshot.timeSignatureChanges
        midiEvents = snapshot.midiEvents
        snapshot.applyMetadata(to: song)
        snapshot.applyTracks(to: song, context: context)

        XCTAssertEqual(song.baseKeyRaw, "Bb")
        XCTAssertEqual(song.displayedKeyText, "C")

        let restored = SongEditSnapshot.capture(
            song: song,
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents
        )

        XCTAssertEqual(restored, snapshot)
    }
}
