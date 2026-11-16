import XCTest
@testable import CuesLive

final class LiveLaneWindowTests: XCTestCase {
    private let window = LiveLaneWindow(start: 10, end: 30)

    func testInPointSitsAtTheLaneStartAndOutPointAtItsEnd() {
        XCTAssertEqual(window.x(for: 10, width: 200), 0)
        XCTAssertEqual(window.x(for: 20, width: 200), 100)
        XCTAssertEqual(window.x(for: 30, width: 200), 200)
    }

    func testTimesOutsideTheWindowPinToTheLaneEnds() {
        XCTAssertEqual(window.x(for: 2, width: 200), 0)
        XCTAssertEqual(window.x(for: 45, width: 200), 200)
    }

    func testLaneXMapsBackToTimelineTime() {
        XCTAssertEqual(window.time(at: 50, width: 200), 15)
    }

    func testClipsAreCutToTheWindowAndStartAtZero() {
        let trackID = UUID()
        let clips = [
            TrackClip(trackID: trackID, timelineStartSeconds: 0, duration: 5, sourceStartSeconds: 0),
            TrackClip(trackID: trackID, timelineStartSeconds: 5, duration: 20, sourceStartSeconds: 5, playbackRate: 2),
            TrackClip(trackID: trackID, timelineStartSeconds: 28, duration: 10, sourceStartSeconds: 40),
        ]

        let cut = window.laneClips(clips)

        XCTAssertEqual(cut.count, 2)
        XCTAssertEqual(cut[0].timelineStartSeconds, 0)
        XCTAssertEqual(cut[0].duration, 15)
        XCTAssertEqual(cut[0].sourceStartSeconds, 15, "Five timeline seconds in, at double speed.")
        XCTAssertEqual(cut[1].timelineStartSeconds, 18)
        XCTAssertEqual(cut[1].duration, 2)
        XCTAssertEqual(cut[1].sourceStartSeconds, 40)
    }

    func testWaveformSourceDrawsOnlyThePlayedStretch() {
        let trackID = UUID()
        let clip = TrackClip(trackID: trackID, timelineStartSeconds: 0, duration: 120, sourceStartSeconds: 0)
        let snapshot = LiveSongWaveformSnapshot(
            songID: UUID(),
            songName: "Song",
            trackSources: [(URL(fileURLWithPath: "/tmp/a.wav"), 120)],
            trackClips: [[clip]],
            fileDuration: 120,
            startTime: 10,
            timelineDuration: 90,
            sections: [],
            peakClips: [clip],
            tempoChanges: [],
            timeSignatureChanges: [],
            showsMeasureGrid: false
        )

        let source = LiveSetlistWaveformSource(snapshot)

        XCTAssertEqual(source.timelineDuration, 80)
        XCTAssertEqual(source.tracks.first?.clips?.first?.sourceStartSeconds, 10)
        XCTAssertEqual(source.clips.first?.duration, 80)
        XCTAssertEqual(snapshot.contentWidth, TimelineLayout.contentWidth(for: 80))
    }

    func testRemoteSongWithoutInPointDecodesFromTheStart() throws {
        let song = RemoteSongDTO(
            id: UUID(),
            name: "Song",
            fileDuration: 60,
            startTime: 4,
            timelineDuration: 60,
            key: "",
            sections: [],
            peakSections: [],
            loopSectionIDs: [],
            tempoChanges: [],
            timeSignatureChanges: [],
            showsMeasureGrid: false,
            peaks: [],
            smartGuideEnabled: false
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(song)) as? [String: Any])
        XCTAssertEqual(json["startTime"] as? Double, 4)
        json.removeValue(forKey: "startTime")

        let decoded = try JSONDecoder().decode(RemoteSongDTO.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(decoded.startTime, 0)
    }
}
