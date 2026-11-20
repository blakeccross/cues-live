import XCTest
@testable import CuesLive

final class SongPlayRangeTests: XCTestCase {
    private let minimum = SongPlayRange.minimumLength

    private func timeline(contentEnd: TimeInterval, playRange: SongPlayRange = SongPlayRange()) -> SongTimeline {
        SongTimeline(
            clips: [TrackClip(trackID: UUID(), timelineStartSeconds: 0, duration: contentEnd, sourceStartSeconds: 0)],
            playRange: playRange
        )
    }

    // MARK: - Resolving

    func testDefaultRangePlaysTheWholeSong() {
        XCTAssertEqual(SongPlayRange().resolved(songEnd: 30), 0...30)
    }

    func testOutPointFollowsTheContentUntilSet() {
        let range = SongPlayRange(startSeconds: 4)

        XCTAssertEqual(range.resolved(songEnd: 30), 4...30)
        XCTAssertEqual(range.resolved(songEnd: 45), 4...45)
    }

    func testOutPointMayRunPastTheContent() {
        XCTAssertEqual(SongPlayRange(endSeconds: 40).resolved(songEnd: 30), 0...40)
    }

    func testResolvedRangeKeepsTheMinimumLength() {
        let range = SongPlayRange(startSeconds: 10, endSeconds: 5)

        XCTAssertEqual(range.resolved(songEnd: 30), 10...(10 + minimum))
    }

    func testNegativeInPointResolvesToZero() {
        XCTAssertEqual(SongPlayRange(startSeconds: -3).resolved(songEnd: 30), 0...30)
    }

    // MARK: - Moving a point

    func testMovingTheInPointKeepsTheOutPointFollowingTheSong() {
        let moved = SongPlayRange().moving(.start, to: 6, songEnd: 30, limit: 60)

        XCTAssertEqual(moved, SongPlayRange(startSeconds: 6, endSeconds: nil))
    }

    func testInPointStopsShortOfTheOutPoint() {
        let moved = SongPlayRange(endSeconds: 20).moving(.start, to: 25, songEnd: 30, limit: 60)

        XCTAssertEqual(moved.startSeconds, 20 - minimum)
    }

    func testInPointNeverMovesBeforeZero() {
        let moved = SongPlayRange(startSeconds: 4).moving(.start, to: -2, songEnd: 30, limit: 60)

        XCTAssertEqual(moved.startSeconds, 0)
    }

    func testOutPointStopsShortOfTheInPoint() {
        let moved = SongPlayRange(startSeconds: 10).moving(.end, to: 3, songEnd: 30, limit: 60)

        XCTAssertEqual(moved, SongPlayRange(startSeconds: 10, endSeconds: 10 + minimum))
    }

    func testOutPointNeverMovesPastTheLimit() {
        let moved = SongPlayRange().moving(.end, to: 90, songEnd: 30, limit: 60)

        XCTAssertEqual(moved.endSeconds, 60)
    }

    // MARK: - Playback

    func testPlaybackLayoutStartsAtTheInPointAndEndsAtTheOutPoint() {
        let layout = SongPlaybackLayout(timeline: timeline(contentEnd: 30, playRange: SongPlayRange(startSeconds: 4, endSeconds: 25)))

        XCTAssertEqual(layout.startTime, 4)
        XCTAssertEqual(layout.duration, 25)
    }

    func testPlaybackLayoutDropsSectionsPastTheOutPoint() {
        var song = timeline(contentEnd: 30, playRange: SongPlayRange(endSeconds: 15))
        song.markers = [
            ArrangementMarker(name: "Verse", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Outro", startSeconds: 20, sortOrder: 1),
        ]

        let layout = SongPlaybackLayout(timeline: song)

        XCTAssertEqual(layout.sections.map(\.name), ["Verse"])
        XCTAssertEqual(layout.sections.first?.timelineEndSeconds, 15)
    }

    func testPlaybackLayoutCutsSectionsAtTheInPoint() {
        var song = timeline(contentEnd: 30, playRange: SongPlayRange(startSeconds: 12))
        song.markers = [
            ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 10, sortOrder: 1),
            ArrangementMarker(name: "Chorus", startSeconds: 20, sortOrder: 2),
        ]

        let layout = SongPlaybackLayout(timeline: song)

        XCTAssertEqual(layout.sections.map(\.name), ["Verse", "Chorus"])
        XCTAssertEqual(layout.sections.map(\.timelineStartSeconds), [12, 20])
    }

    func testStoppingRewindsToTheInPoint() {
        let engine = AudioEngineManager(sampleRate: DecodedStemBuffer.engineSampleRate)
        engine.setArrangement(SongPlaybackLayout(timeline: timeline(contentEnd: 30, playRange: SongPlayRange(startSeconds: 4))))
        engine.seek(to: 12)

        engine.stop()

        XCTAssertEqual(engine.currentTime, 4)
        XCTAssertEqual(engine.startTime, 4)
    }

    func testLockedTempoChangeMovesTheInAndOutPoints() {
        let signatures = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]
        let lockedID = UUID()
        let song = SongTimeline(
            clips: [TrackClip(trackID: lockedID, timelineStartSeconds: 0, duration: 8, sourceStartSeconds: 0)],
            playRange: SongPlayRange(startSeconds: 2, endSeconds: 6)
        )

        let result = TempoTrackLock.retime(
            song,
            midiEvents: [],
            lockedTrackIDs: [lockedID],
            from: TempoTimeline(tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)], timeSignatureChanges: signatures),
            to: TempoTimeline(tempoChanges: [TempoChange(startMeasure: 1, bpm: 60)], timeSignatureChanges: signatures)
        )

        XCTAssertEqual(result.timeline.playRange.startSeconds, 4, accuracy: 1e-9)
        XCTAssertEqual(result.timeline.playRange.endSeconds ?? 0, 12, accuracy: 1e-9)
    }

    // MARK: - Project files

    func testPlayRangeRoundTripsThroughTheProjectFile() throws {
        let original = timeline(contentEnd: 30, playRange: SongPlayRange(startSeconds: 4, endSeconds: 25))

        let data = try JSONEncoder().encode(SongProjectArrangement(timeline: original))
        let decoded = try JSONDecoder().decode(SongProjectArrangement.self, from: data)

        XCTAssertEqual(decoded.timeline.playRange, original.playRange)
    }
}
