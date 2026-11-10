import XCTest
@testable import CuesLive

final class TempoOperationsTests: XCTestCase {
    private let fourFour = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]

    func testLegacyTempoDecodesWithoutBeatOffset() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","startMeasure":3,"bpm":90,"sortOrder":1}"#
        let change = try JSONDecoder().decode(TempoChange.self, from: Data(json.utf8))
        XCTAssertEqual(change.startMeasure, 3)
        XCTAssertEqual(change.beatOffset, 0)
        XCTAssertEqual(change.bpm, 90)
    }

    func testConstantReplacesInteriorAndRestoresTheEnd() {
        let original = [
            TempoChange(startMeasure: 1, bpm: 100),
            TempoChange(startMeasure: 2, bpm: 140),
        ]
        // Beat 2 of bar 1 through the downbeat of bar 3. Bar 2's 140 sits inside.
        let start = TempoTimeline.tick(measure: 1, beatOffset: 2, timeSignatureChanges: fourFour)
        let end = TempoTimeline.tick(measure: 3, beatOffset: 0, timeSignatureChanges: fourFour)
        let updated = try! TempoOperations.constant(
            bpm: 90,
            from: start,
            to: end,
            tempoChanges: original,
            timeSignatureChanges: fourFour
        ).get()

        let timeline = TempoTimeline(tempoChanges: updated, timeSignatureChanges: fourFour)
        XCTAssertEqual(timeline.bpm(atTick: start - 1), 100)
        XCTAssertEqual(timeline.bpm(atTick: start), 90)
        XCTAssertEqual(timeline.bpm(atTick: TempoChange.ticksPerQuarter * 4), 90, "the interior change is replaced")
        XCTAssertEqual(timeline.bpm(atTick: end), 140, "the old tempo resumes at the end")
        XCTAssertFalse(updated.contains { $0.startMeasure == 2 && $0.isDownbeat && abs($0.bpm - 140) < 0.001 })
    }

    func testLinearRampSamplesQuartersAndKeepsTheEndTempo() {
        let original = [TempoChange(startMeasure: 1, bpm: 120)]
        let end = TempoChange.ticksPerQuarter * 4
        let updated = try! TempoOperations.curve(
            .linear,
            startBPM: 120,
            endBPM: 160,
            from: 0,
            to: end,
            resolutionTicks: TempoResolution.quarter.ticks,
            tempoChanges: original,
            timeSignatureChanges: fourFour
        ).get()

        XCTAssertEqual(updated.count, 5)
        XCTAssertEqual(updated.map(\.bpm), [120, 130, 140, 150, 120])
        let timeline = TempoTimeline(tempoChanges: updated, timeSignatureChanges: fourFour)
        XCTAssertEqual(timeline.bpm(atTick: end), 120)
        XCTAssertEqual(timeline.seconds(atTick: TempoChange.ticksPerQuarter), 0.5, accuracy: 0.0001)
    }

    func testParabolicAndSCurveMatchSoundCraft() {
        let end = TempoChange.ticksPerQuarter * 4
        let parabolic = try! TempoOperations.curve(
            .parabolic,
            startBPM: 120,
            endBPM: 160,
            from: 0,
            to: end,
            resolutionTicks: TempoResolution.quarter.ticks,
            curvature: 0.5,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: fourFour
        ).get()
        // f = 0.5, curvature 0.5 → f² → 120 + 40 * 0.25.
        XCTAssertEqual(parabolic[2].bpm, 130, accuracy: 0.0001)

        let scurve = try! TempoOperations.curve(
            .sCurve,
            startBPM: 120,
            endBPM: 160,
            from: 0,
            to: end,
            resolutionTicks: TempoResolution.quarter.ticks,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: fourFour
        ).get()
        XCTAssertEqual(scurve[2].bpm, 140, accuracy: 0.0001)
    }

    func testStretchHalvesTempoAndDoublesTheRange() {
        let end = TempoChange.ticksPerQuarter * 4
        let updated = try! TempoOperations.stretch(
            factor: 2,
            from: 0,
            to: end,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: fourFour
        ).get()
        let timeline = TempoTimeline(tempoChanges: updated, timeSignatureChanges: fourFour)
        XCTAssertEqual(timeline.bpm(atTick: 0), 60)
        XCTAssertEqual(timeline.bpm(atTick: end), 120)
        XCTAssertEqual(timeline.seconds(atTick: end), 4, accuracy: 0.0001)
    }

    func testRampShortensItsBarAndTheNextBarKeepsTheOldTempo() {
        let end = TempoTimeline.tick(measure: 2, beatOffset: 0, timeSignatureChanges: fourFour)
        let updated = try! TempoOperations.curve(
            .linear,
            startBPM: 120,
            endBPM: 180,
            from: 0,
            to: end,
            resolutionTicks: TempoResolution.eighth.ticks,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: fourFour
        ).get()

        let bar2 = MeasureTiming.timeAtStartOfMeasure(2, tempoChanges: updated, timeSignatureChanges: fourFour)
        let bar3 = MeasureTiming.timeAtStartOfMeasure(3, tempoChanges: updated, timeSignatureChanges: fourFour)
        XCTAssertLessThan(bar2, 2)
        XCTAssertEqual(bar3 - bar2, 2, accuracy: 0.0001)
    }

    func testScaleMultipliesEveryTempo() {
        let updated = try! TempoOperations.scale(
            factor: 0.5,
            tempoChanges: [
                TempoChange(startMeasure: 1, bpm: 120),
                TempoChange(startMeasure: 5, bpm: 80),
            ],
            timeSignatureChanges: fourFour
        ).get()
        XCTAssertEqual(updated.map(\.bpm), [60, 40])
    }

    func testScaleRejectsATempoOutsideTheRange() {
        let result = TempoOperations.scale(
            factor: 0.05,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: fourFour
        )
        guard case .failure(.invalidBPM(_)) = result else {
            return XCTFail("expected an out-of-range tempo")
        }
    }
}
