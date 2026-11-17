import XCTest
@testable import CuesLive

final class OverlapPreviewEngineTests: XCTestCase {
    func testSeekWhileStoppedDoesNotStartPlayback() {
        let engine = OverlapPreviewEngine()

        engine.seek(to: 12)

        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(engine.playheadTime)
    }

    func testPlayBeforeLoadingDoesNothing() {
        let engine = OverlapPreviewEngine()

        engine.play(from: 3, until: 10)

        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(engine.playheadTime)
    }
}
