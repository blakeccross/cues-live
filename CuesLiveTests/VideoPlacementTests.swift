import XCTest
@testable import CuesLive

final class VideoPlacementTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/movie.mov")

    func testTimelineMapsOneToOneFromTheStart() {
        let placement = VideoPlacement(url: url, startSeconds: 4, durationSeconds: 30)
        XCTAssertNil(placement.movieSeconds(atTimeline: 3.9))
        XCTAssertEqual(placement.movieSeconds(atTimeline: 4), 0)
        XCTAssertEqual(placement.movieSeconds(atTimeline: 10.5), 6.5)
        XCTAssertNil(placement.movieSeconds(atTimeline: 34))
    }

    func testNegativeStartBeginsPartwayIntoTheMovie() {
        let placement = VideoPlacement(url: url, startSeconds: -2, durationSeconds: 30)
        XCTAssertEqual(placement.movieSeconds(atTimeline: 0), 2)
    }

    func testUnknownLengthRunsOn() {
        let placement = VideoPlacement(url: url, startSeconds: 0, durationSeconds: nil)
        XCTAssertEqual(placement.movieSeconds(atTimeline: 5000), 5000)
    }

    func testVideoRoundTripsThroughTheProjectFile() throws {
        let video = ProjectVideoTrack(
            id: UUID(),
            displayName: "Lyrics",
            media: MediaReference(path: "Lyrics.mov", pathStyle: .relativeToProject),
            startSeconds: 1.5,
            sourceDurationSeconds: 240,
            laneHeight: 132
        )
        let decoded = try JSONDecoder().decode(ProjectVideoTrack.self, from: JSONEncoder().encode(video))
        XCTAssertEqual(decoded, video)
    }
}
