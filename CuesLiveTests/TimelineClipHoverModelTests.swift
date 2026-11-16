import XCTest
@testable import CuesLive

@MainActor
final class TimelineClipHoverModelTests: XCTestCase {
    private final class CanvasSpy: TimelineClipHoverFollowing {
        var changes: [UUID?] = []

        func hoveredClipDidChange(_ clipID: UUID?) {
            changes.append(clipID)
        }
    }

    func testTellsTheCanvasOnlyWhenTheHoveredClipChanges() {
        let model = TimelineClipHoverModel()
        let canvas = CanvasSpy()
        model.laneCanvas = canvas
        let clip = UUID()

        // The hover callback fires on every pointer move inside the clip.
        model.setClipID(clip)
        model.setClipID(clip)
        model.setClipID(nil)
        model.setClipID(nil)

        XCTAssertEqual(canvas.changes, [clip, nil])
        XCTAssertNil(model.clipID)
    }
}
