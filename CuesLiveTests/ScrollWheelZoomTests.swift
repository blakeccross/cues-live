#if os(macOS)
import AppKit
import XCTest
@testable import CuesLive

final class ScrollWheelZoomTests: XCTestCase {
    func testPlainScrollDoesNotZoom() {
        XCTAssertNil(ScrollWheelZoom.scale(deltaY: 3, hasPreciseDeltas: false, modifiers: []))
        XCTAssertNil(ScrollWheelZoom.scale(deltaY: 3, hasPreciseDeltas: false, modifiers: .shift))
    }

    func testCommandAndOptionScrollZoom() {
        XCTAssertNotNil(ScrollWheelZoom.scale(deltaY: 1, hasPreciseDeltas: false, modifiers: .command))
        XCTAssertNotNil(ScrollWheelZoom.scale(deltaY: 1, hasPreciseDeltas: false, modifiers: .option))
    }

    func testScrollingUpZoomsInAndDownZoomsOut() throws {
        let zoomIn = try XCTUnwrap(ScrollWheelZoom.scale(deltaY: 1, hasPreciseDeltas: false, modifiers: .command))
        let zoomOut = try XCTUnwrap(ScrollWheelZoom.scale(deltaY: -1, hasPreciseDeltas: false, modifiers: .command))
        XCTAssertGreaterThan(zoomIn, 1)
        XCTAssertLessThan(zoomOut, 1)
        XCTAssertEqual(zoomIn * zoomOut, 1, accuracy: 1e-9)
    }

    func testWheelNotchZoomsMoreThanTrackpadPoint() throws {
        let notch = try XCTUnwrap(ScrollWheelZoom.scale(deltaY: 1, hasPreciseDeltas: false, modifiers: .option))
        let point = try XCTUnwrap(ScrollWheelZoom.scale(deltaY: 1, hasPreciseDeltas: true, modifiers: .option))
        XCTAssertGreaterThan(notch, point)
    }
}
#endif
