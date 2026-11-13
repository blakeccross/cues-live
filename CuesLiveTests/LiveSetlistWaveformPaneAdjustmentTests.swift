import XCTest
@testable import CuesLive

final class LiveSetlistWaveformPaneAdjustmentTests: XCTestCase {
    private let laneOverhead = LiveSetlistWaveformMetrics.midiLanesHeight(forRowCount: 1)

    func testInitialMeasurementKeepsAPaneThatAlreadyFitsMIDILanes() {
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: 96 + laneOverhead,
                midiOverhead: laneOverhead,
                storedWaveformHeight: 96
            )
        )

        XCTAssertEqual(decision.waveformHeight, 96)
        XCTAssertTrue(decision.persistWaveformHeight)
    }

    func testInitialShortPaneWaitsInsteadOfSavingAShorterWaveform() {
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: 96,
                midiOverhead: laneOverhead,
                storedWaveformHeight: 96
            )
        )

        XCTAssertNil(decision.waveformHeight)
        XCTAssertFalse(decision.persistWaveformHeight)
    }

    func testMIDILanesAppearingWithoutADividerMoveDoNotChangeTheSavedHeight() {
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: 96,
                midiOverhead: laneOverhead,
                storedWaveformHeight: 96,
                previousAssignedHeight: 96,
                previousMIDIOverhead: 0
            )
        )

        XCTAssertNil(decision.waveformHeight)
        XCTAssertFalse(decision.persistWaveformHeight)
    }

    func testForceFitReservesLaneSpaceWithoutSavingIt() {
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: 96,
                midiOverhead: laneOverhead,
                storedWaveformHeight: 96,
                previousAssignedHeight: 96,
                previousMIDIOverhead: 0,
                forceFit: true
            )
        )

        XCTAssertEqual(decision.waveformHeight, 96 - laneOverhead)
        XCTAssertFalse(decision.persistWaveformHeight)
    }

    func testDividerGrowthForNewLanesKeepsTheSavedWaveformHeight() {
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: 96 + laneOverhead,
                midiOverhead: laneOverhead,
                storedWaveformHeight: 96,
                previousAssignedHeight: 96,
                previousMIDIOverhead: 0
            )
        )

        XCTAssertEqual(decision.waveformHeight, 96)
        XCTAssertFalse(decision.persistWaveformHeight)
    }

    func testSettlingUpFromTheMinimumDoesNotSaveAShorterWaveform() {
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: 96,
                midiOverhead: laneOverhead,
                storedWaveformHeight: 96,
                previousAssignedHeight: LiveSetlistWaveformMetrics.minimumWaveformHeight,
                previousMIDIOverhead: laneOverhead
            )
        )

        XCTAssertNil(decision.waveformHeight)
        XCTAssertFalse(decision.persistWaveformHeight)
    }

    func testUserResizePersistsTheWaveformHeight() {
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: 140,
                midiOverhead: laneOverhead,
                storedWaveformHeight: 96,
                previousAssignedHeight: 96 + laneOverhead,
                previousMIDIOverhead: laneOverhead
            )
        )

        XCTAssertEqual(decision.waveformHeight, 140 - laneOverhead)
        XCTAssertTrue(decision.persistWaveformHeight)
    }

    func testReservationIsTheSavedWaveformPlusMIDILanes() {
        XCTAssertEqual(
            LiveSetlistWaveformPaneAdjustment.reservedPaneHeight(
                storedWaveformHeight: 96,
                midiOverhead: laneOverhead,
                isReserving: true
            ),
            96 + laneOverhead
        )
        XCTAssertNil(
            LiveSetlistWaveformPaneAdjustment.reservedPaneHeight(
                storedWaveformHeight: 96,
                midiOverhead: laneOverhead,
                isReserving: false
            )
        )
        XCTAssertNil(
            LiveSetlistWaveformPaneAdjustment.reservedPaneHeight(
                storedWaveformHeight: 96,
                midiOverhead: 0,
                isReserving: true
            )
        )
    }
}
