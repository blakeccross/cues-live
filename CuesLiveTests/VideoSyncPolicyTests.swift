import XCTest
@testable import CuesLive

final class VideoSyncPolicyTests: XCTestCase {
    private func player(
        at seconds: TimeInterval,
        running: Bool,
        seeking: Bool = false,
        sinceLock: TimeInterval = 10
    ) -> VideoSyncPolicy.PlayerState {
        VideoSyncPolicy.PlayerState(
            seconds: seconds,
            isRunning: running,
            isSeeking: seeking,
            secondsSinceLastLock: sinceLock
        )
    }

    func testOutsideTheMovieHidesThePicture() {
        XCTAssertEqual(
            VideoSyncPolicy.action(target: nil, isTransportPlaying: true, player: player(at: 3, running: true)),
            .hide
        )
    }

    func testStartingPlaybackLocksThePlayerToTheAudio() {
        XCTAssertEqual(
            VideoSyncPolicy.action(target: 12, isTransportPlaying: true, player: player(at: 0, running: false)),
            .play(from: 12)
        )
    }

    func testSmallDriftWhilePlayingIsLeftAlone() {
        XCTAssertEqual(
            VideoSyncPolicy.action(target: 12, isTransportPlaying: true, player: player(at: 12.02, running: true)),
            .none
        )
    }

    func testSectionJumpWhilePlayingRelocks() {
        XCTAssertEqual(
            VideoSyncPolicy.action(target: 40, isTransportPlaying: true, player: player(at: 12, running: true)),
            .play(from: 40)
        )
    }

    func testDriftRightAfterARelockWaitsForTheDecoder() {
        XCTAssertEqual(
            VideoSyncPolicy.action(
                target: 40,
                isTransportPlaying: true,
                player: player(at: 12, running: true, sinceLock: 0.1)
            ),
            .none
        )
    }

    func testStoppingTheAudioStopsThePicture() {
        XCTAssertEqual(
            VideoSyncPolicy.action(target: 8, isTransportPlaying: false, player: player(at: 8, running: true)),
            .pause(at: 8)
        )
    }

    func testScrubbingWhileStoppedSeeksOnceAtATime() {
        XCTAssertEqual(
            VideoSyncPolicy.action(target: 20, isTransportPlaying: false, player: player(at: 8, running: false)),
            .seek(to: 20)
        )
        XCTAssertEqual(
            VideoSyncPolicy.action(
                target: 20,
                isTransportPlaying: false,
                player: player(at: 8, running: false, seeking: true)
            ),
            .none
        )
    }
}
