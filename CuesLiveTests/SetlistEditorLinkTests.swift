import XCTest
@testable import CuesLive

@MainActor
final class SetlistEditorLinkTests: XCTestCase {
    func testAttachedCoordinatorIsFollowable() {
        let link = SetlistEditorLink()
        let coordinator = PlaybackCoordinator()

        link.attach(coordinator)

        XCTAssertTrue(link.followableCoordinator === coordinator)
    }

    func testInlineEditorHidesCoordinatorUntilClosed() {
        let link = SetlistEditorLink()
        let coordinator = PlaybackCoordinator()
        link.attach(coordinator)

        link.setInlineEditorOpen(true)
        XCTAssertNil(link.followableCoordinator)

        link.setInlineEditorOpen(false)
        XCTAssertTrue(link.followableCoordinator === coordinator)
    }

    func testDetachingStaleCoordinatorKeepsCurrentOne() {
        let link = SetlistEditorLink()
        let stale = PlaybackCoordinator()
        let current = PlaybackCoordinator()
        link.attach(stale)
        link.attach(current)

        link.detach(stale)

        XCTAssertTrue(link.coordinator === current)
    }

    func testDetachClearsCoordinatorButKeepsInlineEditorFlag() {
        let link = SetlistEditorLink()
        let coordinator = PlaybackCoordinator()
        link.attach(coordinator)
        link.setInlineEditorOpen(true)

        link.detach(coordinator)

        XCTAssertNil(link.coordinator)
        XCTAssertTrue(link.isInlineEditorOpen)
    }

    func testEditPinsSongUntilSetlistReachesIt() {
        let link = SetlistEditorLink()
        link.attach(PlaybackCoordinator())
        let songID = UUID()

        link.edit(songID)
        XCTAssertEqual(link.pinnedSongID, songID)

        link.activeSongDidChange(to: UUID())
        XCTAssertEqual(link.pinnedSongID, songID)

        link.activeSongDidChange(to: songID)
        XCTAssertNil(link.pinnedSongID)
    }

    func testFollowSetlistAndClosingWindowDropPin() {
        let link = SetlistEditorLink()
        link.attach(PlaybackCoordinator())
        link.setWindowOpen(true)

        link.edit(UUID())
        link.followSetlist()
        XCTAssertNil(link.pinnedSongID)

        link.edit(UUID())
        link.setWindowOpen(false)
        XCTAssertNil(link.pinnedSongID)
        XCTAssertFalse(link.isWindowOpen)
    }
}
