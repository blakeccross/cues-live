import XCTest
@testable import CuesLive

final class SongUndoControllerTests: XCTestCase {
    private func makeSnapshot(markers: Int = 0) -> SongEditSnapshot {
        SongEditSnapshot(
            markers: (0..<markers).map { index in
                ArrangementMarker(
                    name: "Section \(index + 1)",
                    startSeconds: TimeInterval(index),
                    sortOrder: index
                )
            },
            arrangementSlots: [],
            clipTrims: [],
            removedClips: [],
            clipGaps: [],
            clipRegions: [],
            loopSlotIDs: [],
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [
                TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0)
            ],
            midiEvents: [],
            songMetadata: SongMetadataSnapshot(
                bpm: 120,
                timeSignatureNumerator: 4,
                timeSignatureDenominator: 4,
                baseKeyRaw: nil,
                transposeSemitones: 0,
                transposeHighQuality: false,
                smartGuideEnabled: false
            ),
            tracks: []
        )
    }

    func testUndoRedoRoundTrip() {
        let controller = SongUndoController()
        var current = makeSnapshot()

        controller.registerChange(
            actionName: "Add Section",
            before: current,
            after: makeSnapshot(markers: 1),
            apply: { current = $0 }
        )

        XCTAssertTrue(controller.canUndo)
        XCTAssertFalse(controller.canRedo)

        controller.undo()
        XCTAssertEqual(current.markers.count, 0)
        XCTAssertFalse(controller.canUndo)
        XCTAssertTrue(controller.canRedo)

        controller.redo()
        XCTAssertEqual(current.markers.count, 1)
        XCTAssertTrue(controller.canUndo)
        XCTAssertFalse(controller.canRedo)
    }

    func testRedoStackClearsAfterNewEdit() {
        let controller = SongUndoController()
        var current = makeSnapshot()

        let first = makeSnapshot(markers: 1)
        controller.registerChange(
            actionName: "First",
            before: current,
            after: first,
            apply: { current = $0 }
        )
        current = first
        controller.undo()

        let second = makeSnapshot(markers: 2)
        controller.registerChange(
            actionName: "Second",
            before: current,
            after: second,
            apply: { current = $0 }
        )
        current = second

        XCTAssertFalse(controller.canRedo)
        XCTAssertEqual(current.markers.count, 2)
    }

    func testSkipsRegistrationWhenSnapshotsMatch() {
        let controller = SongUndoController()
        let snapshot = makeSnapshot()

        controller.registerChange(
            actionName: "No-op",
            before: snapshot,
            after: snapshot,
            apply: { _ in }
        )

        XCTAssertFalse(controller.canUndo)
    }
}
