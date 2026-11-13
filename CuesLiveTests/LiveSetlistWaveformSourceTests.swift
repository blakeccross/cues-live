import XCTest
@testable import CuesLive

final class LiveSetlistWaveformSourceTests: XCTestCase {
    private func snapshot(
        tracks: [(url: URL, duration: TimeInterval)] = [(URL(fileURLWithPath: "/tmp/a.wav"), 120)],
        sections: [SongSection] = [],
        clips: [TrackClip] = [],
        peaks: [Float]? = nil,
        audioRevision: Int = 0,
        trackClips: [[TrackClip]] = []
    ) -> LiveSongWaveformSnapshot {
        LiveSongWaveformSnapshot(
            songID: UUID(),
            songName: "Song",
            trackSources: tracks,
            trackClips: trackClips,
            fileDuration: 120,
            timelineDuration: 120,
            sections: sections,
            peakClips: clips,
            tempoChanges: [],
            timeSignatureChanges: [],
            showsMeasureGrid: false,
            precomputedSourcePeaks: peaks,
            audioRevision: audioRevision
        )
    }

    private let clipID = UUID()
    private let trackID = UUID()

    private func clip(start: TimeInterval) -> TrackClip {
        TrackClip(id: clipID, trackID: trackID, timelineStartSeconds: start, duration: 10, sourceStartSeconds: 0)
    }

    func testSameInputsShareAKeyAcrossSongs() {
        XCTAssertEqual(LiveSetlistWaveformSource(snapshot()), LiveSetlistWaveformSource(snapshot()))
    }

    func testMovingAClipChangesTheKey() {
        let section = SongSection(id: UUID(), name: "Verse", timelineStartSeconds: 0, timelineEndSeconds: 60, loops: false)
        let before = LiveSetlistWaveformSource(snapshot(sections: [section], clips: [clip(start: 0)]))
        let after = LiveSetlistWaveformSource(snapshot(sections: [section], clips: [clip(start: 5)]))
        XCTAssertNotEqual(before, after)
    }

    func testRewritingAStemInPlaceChangesTheKey() {
        let before = LiveSetlistWaveformSource(snapshot(audioRevision: 1))
        let after = LiveSetlistWaveformSource(snapshot(audioRevision: 2))
        XCTAssertNotEqual(before, after, "same paths and durations, new file contents")
    }

    func testTrimmingATrackChangesTheKey() {
        let before = LiveSetlistWaveformSource(snapshot(trackClips: [[clip(start: 0)]]))
        let trimmed = TrackClip(id: clipID, trackID: trackID, timelineStartSeconds: 0, duration: 4, sourceStartSeconds: 0)
        let after = LiveSetlistWaveformSource(snapshot(trackClips: [[trimmed]]))
        XCTAssertNotEqual(before, after)
    }

    func testReadsTrackClipsOnlyWhenEveryTrackHasThem() {
        XCTAssertTrue(LiveSetlistWaveformSource(snapshot(trackClips: [[]])).readsTrackClips)
        XCTAssertFalse(LiveSetlistWaveformSource(snapshot()).readsTrackClips, "remote songs map through peak clips")
    }

    func testSongsWithoutSectionsShowTheFilesAsTheyAre() {
        let source = LiveSetlistWaveformSource(snapshot(clips: [clip(start: 0)]))
        XCTAssertTrue(source.clips.isEmpty)
    }

    func testNothingToLoadWithoutTracksOrPeaks() {
        XCTAssertFalse(LiveSetlistWaveformSource(snapshot(tracks: [])).hasAudio)
        XCTAssertFalse(LiveSetlistWaveformSource(snapshot(tracks: [], peaks: [])).hasAudio)
        XCTAssertTrue(LiveSetlistWaveformSource(snapshot(tracks: [], peaks: [0.5])).hasAudio)
    }
}
