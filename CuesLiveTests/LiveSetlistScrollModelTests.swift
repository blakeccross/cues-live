import XCTest
@testable import CuesLive

@MainActor
final class LiveSetlistScrollModelTests: XCTestCase {
    /// Two 100 s songs, 2,000 pt each, with a gap between them, in a 600 pt viewport.
    private func makeModel() -> LiveSetlistScrollModel {
        let model = LiveSetlistScrollModel()
        model.setViewportWidth(600)
        model.setContentWidth(4_200)
        model.setLane(lane(minX: 100, width: 2_000), at: 0)
        model.setLane(lane(minX: 2_200, width: 2_000), at: 1)
        return model
    }

    private func lane(minX: CGFloat, width: CGFloat) -> LiveSetlistScrollModel.Lane {
        LiveSetlistScrollModel.Lane(frame: CGRect(x: minX, y: 4, width: width, height: 96), duration: 100)
    }

    /// Applies the model's target the way the host does.
    private func settle(_ model: LiveSetlistScrollModel) {
        if let target = model.targetOffset() {
            model.didScroll(to: target, byUser: false)
        }
    }

    func testFollowingCentersThePlayhead() {
        let model = makeModel()
        model.setPlayheadTime(50)

        // Playhead at 100 + 1,000 = 1,100; centered in 600 pt is offset 800.
        XCTAssertEqual(model.targetOffset(), 800)
    }

    func testFollowingClampsAtTheStartAndEndOfTheStrip() {
        let model = makeModel()
        model.setPlayheadTime(1)
        XCTAssertNil(model.targetOffset(), "already at offset 0")

        model.setCurrentIndex(1)
        model.setPlayheadTime(100)
        XCTAssertEqual(model.targetOffset(), 3_600)
    }

    func testUserScrollStopsFollowing() {
        let model = makeModel()
        model.setPlayheadTime(50)
        settle(model)

        model.beginUserScroll()
        XCTAssertNil(model.targetOffset(), "never fights the user's finger")
        model.didScroll(to: 2_000, byUser: true)
        model.endUserScroll()

        XCTAssertFalse(model.isFollowing)
        model.setPlayheadTime(51)
        XCTAssertNil(model.targetOffset())
    }

    func testFollowingResumesWhenThePlayheadReachesTheCenter() {
        let model = makeModel()
        model.setPlayheadTime(50)
        settle(model)
        model.didScroll(to: 1_000, byUser: true)
        XCTAssertFalse(model.isFollowing)

        // Center of the viewport is now 1,300, i.e. 60 s into the first song.
        model.setPlayheadTime(56)
        XCTAssertFalse(model.isFollowing, "1,220 is outside the relatch distance")
        model.setPlayheadTime(59)
        XCTAssertTrue(model.isFollowing)
    }

    func testZoomKeepsTheContentUnderThePlayheadWhenNotFollowing() {
        let model = makeModel()
        model.setPlayheadTime(50)
        model.didScroll(to: 500, byUser: true)
        // Playhead at 1,100 sits 600 pt into the viewport, off its right edge.
        model.anchorPlayheadForZoom()

        // Zoom doubles the first lane; the second moves right.
        model.setContentWidth(6_200)
        model.setLane(lane(minX: 100, width: 4_000), at: 0)
        model.setLane(lane(minX: 4_200, width: 2_000), at: 1)

        // Playhead now at 2,100; keeping it 600 pt in needs offset 1,500.
        XCTAssertEqual(model.targetOffset(), 1_500)
    }

    func testAnchorHoldsTheZoomTimeWhilePlaybackContinues() {
        let model = makeModel()
        model.setPlayheadTime(50)
        model.didScroll(to: 500, byUser: true)
        model.anchorPlayheadForZoom()
        model.setLane(lane(minX: 100, width: 4_000), at: 0)
        model.setContentWidth(6_200)
        settle(model)

        model.setPlayheadTime(52)
        XCTAssertNil(model.targetOffset(), "the strip stays put as the playhead moves on")
    }

    func testSongChangeWhileNotFollowingRevealsTheNewLane() {
        let model = makeModel()
        model.didScroll(to: 300, byUser: true)
        model.setPlayheadTime(0)

        model.setCurrentIndex(1)

        XCTAssertEqual(model.targetOffset(), 2_200)
    }

    func testSongChangeWhileFollowingCentersTheNewPlayhead() {
        let model = makeModel()
        model.setPlayheadTime(50)
        settle(model)

        model.setCurrentIndex(1)
        model.setPlayheadTime(20)

        // 2,200 + 400 = 2,600, centered at 2,300.
        XCTAssertEqual(model.targetOffset(), 2_300)
    }

    func testRetainingLanesKeepsTheCurrentSongsPlayhead() {
        let model = makeModel()
        model.setCurrentIndex(1)
        model.setPlayheadTime(10)

        model.retainLanes(at: [0, 1])
        XCTAssertNotNil(model.playheadFrame(width: 2))

        model.retainLanes(at: [0])
        XCTAssertNil(model.playheadFrame(width: 2), "the second song left the setlist")
    }

    func testPlayheadFrameSitsOnTheCurrentLane() {
        let model = makeModel()
        model.setPlayheadTime(25)

        XCTAssertEqual(model.playheadFrame(width: 2), CGRect(x: 599, y: 4, width: 2, height: 96))
        model.setLane(nil, at: 0)
        XCTAssertNil(model.playheadFrame(width: 2))
    }

    func testIdleTimeDrivesThePlayheadWhileStopped() {
        let model = makeModel()
        model.currentTime = { 80 }
        model.isPlaying = { false }
        model.idleTime = 10

        model.refreshPlayhead()
        XCTAssertEqual(model.playheadTime, 10)
        XCTAssertFalse(model.needsClock)

        model.isPlaying = { true }
        model.refreshPlayhead()
        XCTAssertEqual(model.playheadTime, 80)
        XCTAssertTrue(model.needsClock)
    }
}
