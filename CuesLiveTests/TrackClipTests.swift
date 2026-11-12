import XCTest
@testable import CuesLive

final class TrackClipTests: XCTestCase {
    private let trackID = UUID()

    func testClipsSavedBeforePlaybackRateDecodeAtOriginalSpeed() throws {
        let json = """
        {"id":"\(UUID().uuidString)","trackID":"\(trackID.uuidString)",
         "timelineStartSeconds":2,"duration":4,"sourceStartSeconds":1,"gainDB":0}
        """
        let clip = try JSONDecoder().decode(TrackClip.self, from: Data(json.utf8))
        XCTAssertEqual(clip.playbackRate, 1)
        XCTAssertTrue(clip.playsAtOriginalSpeed)
    }

    func testPlaybackRateRoundTrips() throws {
        let clip = TrackClip(
            trackID: trackID,
            timelineStartSeconds: 0,
            duration: 4,
            sourceStartSeconds: 0,
            playbackRate: 1.25
        )
        let decoded = try JSONDecoder().decode(TrackClip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(decoded, clip)
    }

    func testRateScalesTheStretchOfFilePlayed() {
        let clip = TrackClip(
            trackID: trackID,
            timelineStartSeconds: 10,
            duration: 4,
            sourceStartSeconds: 2,
            playbackRate: 2
        )
        XCTAssertEqual(clip.sourceTime(atTimeline: 11), 4)
        XCTAssertEqual(clip.sourceEndSeconds, 10)
        XCTAssertEqual(clip.timelineTime(atSource: 6), 12)
    }

    func testSplittingAReTimedClipKeepsItsRate() throws {
        let clip = TrackClip(
            trackID: trackID,
            timelineStartSeconds: 0,
            duration: 4,
            sourceStartSeconds: 0,
            playbackRate: 0.5
        )
        var clips = [clip]
        let rightID = ClipEditing.split(clipID: clip.id, at: 2, in: &clips)
        let right = try XCTUnwrap(clips.first { $0.id == rightID })

        XCTAssertEqual(right.playbackRate, 0.5)
        XCTAssertEqual(right.sourceStartSeconds, 1)
        XCTAssertEqual(ClipEditing.joinWithNext(clipID: clip.id, in: &clips), clip.id)
        XCTAssertEqual(clips, [clip])
    }

    func testClipsAtDifferentRatesDoNotJoin() {
        let left = TrackClip(trackID: trackID, timelineStartSeconds: 0, duration: 2, sourceStartSeconds: 0)
        let right = TrackClip(
            trackID: trackID,
            timelineStartSeconds: 2,
            duration: 2,
            sourceStartSeconds: 2,
            playbackRate: 2
        )
        var clips = [left, right]
        XCTAssertNil(ClipEditing.joinWithNext(clipID: left.id, in: &clips))
    }

    func testTrimmingAReTimedClipStopsAtTheFileEdges() {
        // Twice as fast from 1 s into the file: the file's start sits at timeline 9.5.
        let clip = TrackClip(
            trackID: trackID,
            timelineStartSeconds: 10,
            duration: 2,
            sourceStartSeconds: 1,
            playbackRate: 2
        )
        let leading = ClipEditing.trimmed(clip, edge: .leading, to: 0, sourceDuration: 8)
        XCTAssertEqual(leading.timelineStartSeconds, 9.5, accuracy: 1e-9)
        XCTAssertEqual(leading.sourceStartSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(leading.timelineEndSeconds, 12, accuracy: 1e-9)

        let trailing = ClipEditing.trimmed(clip, edge: .trailing, to: 100, sourceDuration: 8)
        XCTAssertEqual(trailing.timelineEndSeconds, 13.5, accuracy: 1e-9)
        XCTAssertEqual(trailing.sourceEndSeconds, 8, accuracy: 1e-9)
    }
}
