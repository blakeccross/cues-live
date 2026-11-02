import XCTest
@testable import CuesLive

final class SmartGuideCallPlannerTests: XCTestCase {
    /// One measure at 120 BPM in 4/4.
    private let lead: TimeInterval = 2
    private let step: TimeInterval = 0.1

    private var verse: ArrangementDisplaySection { section("Verse", start: 0, end: 16) }
    private var chorus: ArrangementDisplaySection { section("Chorus", start: 16, end: 32) }
    private var bridge: ArrangementDisplaySection { section("Bridge", start: 32, end: 48) }
    private var sections: [ArrangementDisplaySection] { [verse, chorus, bridge] }

    func testCallsNextSectionOneMeasureBeforeBoundary() {
        var planner = SmartGuideCallPlanner()
        let calls = play(&planner, from: 0, to: 20)

        XCTAssertEqual(calls.map(\.name), ["Chorus"])
        XCTAssertEqual(calls.first?.boundary, 16)
    }

    func testCallsEachBoundaryOnceAcrossSong() {
        var planner = SmartGuideCallPlanner()
        let calls = play(&planner, from: 0, to: 40)

        XCTAssertEqual(calls.map(\.name), ["Chorus", "Bridge"])
    }

    func testCallFiresAtLeadPointNotAfterBoundary() {
        var planner = SmartGuideCallPlanner()
        var firedAt: TimeInterval?
        var time = 0.0
        while time < 20 {
            if planner.evaluate(at: time, sections: sections, cue: nil, loop: nil, leadDuration: { _ in lead }) != nil {
                firedAt = time
                break
            }
            time += step
        }

        XCTAssertNotNil(firedAt)
        XCTAssertEqual(firedAt ?? 0, 14, accuracy: step)
    }

    func testNoCallAfterFinalSection() {
        var planner = SmartGuideCallPlanner()
        let calls = play(&planner, from: 33, to: 47)

        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - Queued cues

    func testQueuedCueWithRunwayCallsCueNameAtLeadPoint() {
        var planner = SmartGuideCallPlanner()
        let cue = SmartGuideCallPlanner.Cue(name: "Bridge", fireTime: 16)
        let calls = play(&planner, from: 4, to: 17, cue: cue)

        XCTAssertEqual(calls.map(\.name), ["Bridge"])
    }

    func testCueQueuedInsideFinalMeasureIsTooLateAndStaysSilent() {
        var planner = SmartGuideCallPlanner()
        _ = play(&planner, from: 0, to: 2)
        // Playback lands inside the final measure before the boundary (no natural call fires).
        XCTAssertTrue(play(&planner, from: 15, to: 15.5).isEmpty)

        // The user queues a cue after the one-measure point already passed.
        let cue = SmartGuideCallPlanner.Cue(name: "Bridge", fireTime: 16)
        let calls = play(&planner, from: 15.5, to: 17, cue: cue)

        XCTAssertTrue(calls.isEmpty)
    }

    func testCueQueuedBeforeLeadPointBeatsNaturalNextSectionName() {
        var planner = SmartGuideCallPlanner()
        _ = play(&planner, from: 0, to: 8)

        let cue = SmartGuideCallPlanner.Cue(name: "Bridge", fireTime: 16)
        let calls = play(&planner, from: 8, to: 17, cue: cue)

        XCTAssertEqual(calls.map(\.name), ["Bridge"])
    }

    func testCueQueuedAfterNaturalCallDoesNotCallAgain() {
        var planner = SmartGuideCallPlanner()
        let natural = play(&planner, from: 0, to: 14.5)
        XCTAssertEqual(natural.map(\.name), ["Chorus"])

        let cue = SmartGuideCallPlanner.Cue(name: "Bridge", fireTime: 16)
        let calls = play(&planner, from: 14.5, to: 17, cue: cue)

        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - Loops

    func testLoopCallsLoopedSectionNameOnEveryPass() {
        var planner = SmartGuideCallPlanner()
        var calls: [SmartGuideCall] = []
        for _ in 0..<3 {
            calls += play(&planner, from: 16, to: 32, loop: chorus)
        }

        XCTAssertEqual(calls.map(\.name), ["Chorus", "Chorus", "Chorus"])
        XCTAssertTrue(calls.allSatisfy { $0.boundary == 32 })
    }

    func testLoopDoesNotCallNextSection() {
        var planner = SmartGuideCallPlanner()
        let calls = play(&planner, from: 16, to: 32, loop: chorus)

        XCTAssertFalse(calls.contains { $0.name == "Bridge" })
    }

    func testLoopEngagingInsideFinalMeasureSkipsThatPass() {
        var planner = SmartGuideCallPlanner()
        _ = play(&planner, from: 0, to: 2)

        // Playback lands in the last measure of the looping section: too late to call.
        let calls = play(&planner, from: 31, to: 32, loop: chorus)
        XCTAssertTrue(calls.isEmpty)

        // The next pass, after the wrap, is called normally.
        let nextPass = play(&planner, from: 16, to: 32, loop: chorus)
        XCTAssertEqual(nextPass.map(\.name), ["Chorus"])
    }

    func testOneMeasureLoopCallsEveryPass() {
        var planner = SmartGuideCallPlanner()
        let tag = section("Tag", start: 40, end: 42)
        let sections = [tag]
        var calls: [SmartGuideCall] = []
        for _ in 0..<3 {
            var time = 40.0
            while time < 42 {
                if let call = planner.evaluate(
                    at: time,
                    sections: sections,
                    cue: nil,
                    loop: tag,
                    leadDuration: { _ in lead }
                ) {
                    calls.append(call)
                }
                time += step
            }
        }

        XCTAssertEqual(calls.count, 3)
    }

    func testEndingLoopResumesNextSectionCall() {
        var planner = SmartGuideCallPlanner()
        _ = play(&planner, from: 16, to: 32, loop: chorus)

        // Loop ended while the playhead is back at the start of the section.
        let calls = play(&planner, from: 16, to: 32)
        XCTAssertEqual(calls.map(\.name), ["Bridge"])
    }

    // MARK: - Seeks

    func testSeekIntoFinalMeasureStaysSilent() {
        var planner = SmartGuideCallPlanner()
        _ = play(&planner, from: 0, to: 2)

        let calls = play(&planner, from: 15, to: 16.5)
        XCTAssertTrue(calls.isEmpty)
    }

    func testSeekBeforeLeadPointStillCalls() {
        var planner = SmartGuideCallPlanner()
        _ = play(&planner, from: 0, to: 2)

        let calls = play(&planner, from: 8, to: 17)
        XCTAssertEqual(calls.map(\.name), ["Chorus"])
    }

    func testBackwardSeekAllowsBoundaryToCallAgain() {
        var planner = SmartGuideCallPlanner()
        XCTAssertEqual(play(&planner, from: 0, to: 15).map(\.name), ["Chorus"])

        let again = play(&planner, from: 4, to: 15)
        XCTAssertEqual(again.map(\.name), ["Chorus"])
    }

    func testResetClearsArmedState() {
        var planner = SmartGuideCallPlanner()
        _ = play(&planner, from: 0, to: 10)

        planner.reset(at: 15)
        let calls = play(&planner, from: 15, to: 16.5)
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: - Helpers

    private func section(_ name: String, start: TimeInterval, end: TimeInterval) -> ArrangementDisplaySection {
        ArrangementDisplaySection(
            id: UUID(),
            slotID: UUID(),
            markerID: UUID(),
            name: name,
            sourceStartSeconds: start,
            sourceEndSeconds: end,
            timelineStartSeconds: start,
            timelineEndSeconds: end,
            columnStartSeconds: start,
            columnEndSeconds: end
        )
    }

    /// Steps playback in `step` increments from `start` to `end`, returning calls.
    private func play(
        _ planner: inout SmartGuideCallPlanner,
        from start: TimeInterval,
        to end: TimeInterval,
        cue: SmartGuideCallPlanner.Cue? = nil,
        loop: ArrangementDisplaySection? = nil
    ) -> [SmartGuideCall] {
        var calls: [SmartGuideCall] = []
        var time = start
        while time < end {
            if let call = planner.evaluate(
                at: time,
                sections: sections,
                cue: cue,
                loop: loop,
                leadDuration: { _ in lead }
            ) {
                calls.append(call)
            }
            time += step
        }
        return calls
    }
}
