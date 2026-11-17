import XCTest
@testable import CuesLive

@MainActor
final class TimelineHorizontalScrollModelTests: XCTestCase {
    private final class LiveRulerSpy: TimelineLiveZoomFollowing {
        var scales: [CGFloat?] = []
        var offsets: [CGFloat] = []

        func liveZoomDidChange(scale: CGFloat?, offset: CGFloat) {
            scales.append(scale)
        }

        func timelineOffsetDidChange(_ offset: CGFloat) {
            offsets.append(offset)
        }
    }

    /// A 1,000 pt viewport scrolled to 5,000, which paints 4,000...7,000.
    private func makeModel() -> TimelineHorizontalScrollModel {
        let model = TimelineHorizontalScrollModel()
        model.setViewportWidth(1_000)
        model.setOffset(5_000)
        return model
    }

    func testPaintedRangeCoversAScreenEitherSideOfTheViewport() {
        XCTAssertEqual(makeModel().paintedRange, 4_000...7_000)
    }

    func testPaintedRangeStaysInLaidOutCoordinatesWhileZoomingIn() {
        let model = makeModel()

        // Twice the laid-out zoom, centered on the same content: the stretched lanes show
        // laid-out 5,250...5,750, which the painted range already covers.
        model.setLiveZoom(4, laidOutAt: 2)
        model.setOffset(10_500)

        XCTAssertEqual(model.paintedRange, 4_000...7_000)
    }

    func testPaintedRangeFollowsTheOffsetOnceTheZoomIsLaidOut() {
        let model = makeModel()
        model.setLiveZoom(4, laidOutAt: 2)
        model.setOffset(10_500)

        model.setLiveZoom(nil, laidOutAt: 4)

        XCTAssertEqual(model.paintedRange, 9_500...12_500)
    }

    func testLiveRulerFollowsTheLiveZoomAndHidesWhenItIsLaidOut() {
        let model = makeModel()
        let ruler = LiveRulerSpy()
        model.liveRuler = ruler

        model.setLiveZoom(3, laidOutAt: 2)
        model.setOffset(7_500)
        model.setLiveZoom(nil, laidOutAt: 3)

        XCTAssertEqual(ruler.scales, [1.5, nil])
        XCTAssertEqual(ruler.offsets, [7_500])
    }
}
