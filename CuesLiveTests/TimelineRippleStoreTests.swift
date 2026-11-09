import XCTest
@testable import CuesLive

/// Uses 120 BPM in 4/4 throughout, so one measure spans exactly 2 seconds and
/// `timeAtStartOfMeasure(m) == (m - 1) * 2`.
final class TimelineRippleStoreTests: XCTestCase {
    private func defaultTempo() -> [TempoChange] {
        [TempoChange(startMeasure: 1, bpm: 120)]
    }

    private func defaultTimeSignature() -> [TimeSignatureChange] {
        [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0)]
    }

    private func clip(
        trackID: UUID,
        source: TimeInterval,
        timeline: ClosedRange<TimeInterval>,
        id: UUID = UUID()
    ) -> TrackClip {
        TrackClip(
            id: id,
            trackID: trackID,
            timelineStartSeconds: timeline.lowerBound,
            duration: timeline.upperBound - timeline.lowerBound,
            sourceStartSeconds: source
        )
    }

    @discardableResult
    private func ripple(
        start: Int,
        end: Int,
        timeline: inout SongTimeline,
        tempoChanges: inout [TempoChange],
        timeSignatureChanges: inout [TimeSignatureChange],
        midiEvents: inout [MIDIEvent]
    ) -> TimelineRippleStore.Result {
        TimelineRippleStore.rippleDeleteMeasures(
            startMeasure: start,
            endMeasure: end,
            timeline: &timeline,
            tempoChanges: &tempoChanges,
            timeSignatureChanges: &timeSignatureChanges,
            midiEvents: &midiEvents,
            defaultBPM: 120,
            defaultNumerator: 4,
            defaultDenominator: 4
        )
    }

    @discardableResult
    private func ripple(start: Int, end: Int, timeline: inout SongTimeline) -> TimelineRippleStore.Result {
        var tempo = defaultTempo()
        var timeSig = defaultTimeSignature()
        var midi: [MIDIEvent] = []
        return ripple(
            start: start, end: end, timeline: &timeline,
            tempoChanges: &tempo, timeSignatureChanges: &timeSig, midiEvents: &midi
        )
    }

    func testClipAfterWindowShiftsLeft() {
        let trackID = UUID()
        var timeline = SongTimeline(clips: [clip(trackID: trackID, source: 10, timeline: 10...20)])

        // Delete measures 3-4 -> window [4, 8), removedDuration 4.
        ripple(start: 3, end: 5, timeline: &timeline)

        XCTAssertEqual(timeline.clips.count, 1)
        XCTAssertEqual(timeline.clips[0].timelineStartSeconds, 6, accuracy: 0.001)
        XCTAssertEqual(timeline.clips[0].timelineEndSeconds, 16, accuracy: 0.001)
        XCTAssertEqual(timeline.clips[0].sourceStartSeconds, 10, accuracy: 0.001)
    }

    func testClipSpanningWindowSplitsAndClosesGap() {
        let trackID = UUID()
        let clipID = UUID()
        var timeline = SongTimeline(clips: [clip(trackID: trackID, source: 0, timeline: 0...30, id: clipID)])

        // Delete measures 6-10 -> window [10, 20), removedDuration 10.
        ripple(start: 6, end: 11, timeline: &timeline)

        let sorted = timeline.clips(forTrack: trackID)
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].timelineStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(sorted[0].timelineEndSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(sorted[0].id, clipID, "Left piece keeps the original clip id")
        XCTAssertEqual(sorted[1].timelineStartSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(sorted[1].timelineEndSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(sorted[1].sourceStartSeconds, 20, accuracy: 0.001)
        XCTAssertNotEqual(sorted[1].id, clipID, "Right piece gets a fresh id")
    }

    func testClipFullyInsideWindowIsRemovedAndTrackReportedEmpty() {
        let covered = UUID()
        let cleared = UUID()
        var timeline = SongTimeline(clips: [
            clip(trackID: covered, source: 0, timeline: 0...30),
            clip(trackID: cleared, source: 5, timeline: 5...7),
        ])

        // Delete measures 3-4 -> window [4, 8).
        let result = ripple(start: 3, end: 5, timeline: &timeline)

        XCTAssertTrue(timeline.clips(forTrack: cleared).isEmpty)
        XCTAssertFalse(timeline.clips(forTrack: covered).isEmpty)
        XCTAssertEqual(result.emptiedTrackIDs, [cleared])
    }

    func testTempoChangesRenumberByMeasure() {
        var timeline = SongTimeline()
        var tempo = [
            TempoChange(startMeasure: 1, bpm: 120),
            TempoChange(startMeasure: 7, bpm: 140),
        ]
        var timeSig = defaultTimeSignature()
        var midi: [MIDIEvent] = []

        // Delete measures 3-4 -> removedMeasures 2.
        ripple(
            start: 3, end: 5, timeline: &timeline,
            tempoChanges: &tempo, timeSignatureChanges: &timeSig, midiEvents: &midi
        )

        let sorted = tempo.sortedByMeasure
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].startMeasure, 1)
        XCTAssertEqual(sorted[0].bpm, 120, accuracy: 0.001)
        XCTAssertEqual(sorted[1].startMeasure, 5)
        XCTAssertEqual(sorted[1].bpm, 140, accuracy: 0.001)
    }

    func testDeletingFromMeasureOnePromotesLaterTempo() {
        var timeline = SongTimeline()
        var tempo = [
            TempoChange(startMeasure: 1, bpm: 120),
            TempoChange(startMeasure: 3, bpm: 150),
        ]
        var timeSig = defaultTimeSignature()
        var midi: [MIDIEvent] = []

        // Delete measures 1-2 -> the tempo active at measure 3 becomes measure 1.
        ripple(
            start: 1, end: 3, timeline: &timeline,
            tempoChanges: &tempo, timeSignatureChanges: &timeSig, midiEvents: &midi
        )

        let sorted = tempo.sortedByMeasure
        XCTAssertEqual(sorted.first?.startMeasure, 1)
        XCTAssertEqual(sorted.first?.bpm ?? 0, 150, accuracy: 0.001)
    }

    func testTimeSignatureChangesRenumberByMeasure() {
        var timeline = SongTimeline()
        var tempo = defaultTempo()
        var timeSig = [
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0),
            TimeSignatureChange(numerator: 3, denominator: 4, startMeasure: 9, sortOrder: 1),
        ]
        var midi: [MIDIEvent] = []

        // Delete measures 3-4 -> removedMeasures 2.
        ripple(
            start: 3, end: 5, timeline: &timeline,
            tempoChanges: &tempo, timeSignatureChanges: &timeSig, midiEvents: &midi
        )

        let sorted = timeSig.sortedByMeasure
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[1].startMeasure, 7)
        XCTAssertEqual(sorted[1].numerator, 3)
        XCTAssertEqual(sorted[1].denominator, 4)
    }

    func testMarkerInsideWindowMovesToCutWhenItsSectionContinues() {
        var timeline = SongTimeline(markers: [
            ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 5, sortOrder: 1),
            ArrangementMarker(name: "Chorus", startSeconds: 10, sortOrder: 2),
        ])

        // Delete measures 3-4 -> window [4, 8). Verse's 8–10 survives, so its label moves to 4.
        ripple(start: 3, end: 5, timeline: &timeline)

        let sorted = timeline.sortedMarkers
        XCTAssertEqual(sorted.map(\.name), ["Intro", "Verse", "Chorus"])
        XCTAssertEqual(sorted[1].startSeconds, 4, accuracy: 0.001)
        XCTAssertEqual(sorted[2].startSeconds, 6, accuracy: 0.001)
    }

    func testMarkerInsideWindowIsRemovedWhenItsSectionIsGone() {
        var timeline = SongTimeline(markers: [
            ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 5, sortOrder: 1),
            ArrangementMarker(name: "Chorus", startSeconds: 8, sortOrder: 2),
        ])

        // Delete measures 3-4 -> window [4, 8). All of Verse is inside it.
        ripple(start: 3, end: 5, timeline: &timeline)

        let sorted = timeline.sortedMarkers
        XCTAssertEqual(sorted.map(\.name), ["Intro", "Chorus"])
        XCTAssertEqual(sorted[1].startSeconds, 4, accuracy: 0.001)
    }

    func testMidiEventsRemovedAndShifted() {
        var timeline = SongTimeline()
        var tempo = defaultTempo()
        var timeSig = defaultTimeSignature()
        let trackID = UUID()
        var midi = [
            MIDIEvent(trackID: trackID, timelineSeconds: 2, commandID: UUID()),
            MIDIEvent(trackID: trackID, timelineSeconds: 5, commandID: UUID()),
            MIDIEvent(trackID: trackID, timelineSeconds: 10, commandID: UUID()),
        ]

        // Delete measures 3-4 -> window [4, 8), removedDuration 4.
        ripple(
            start: 3, end: 5, timeline: &timeline,
            tempoChanges: &tempo, timeSignatureChanges: &timeSig, midiEvents: &midi
        )

        let times = midi.map(\.timelineSeconds).sorted()
        XCTAssertEqual(times.count, 2)
        XCTAssertEqual(times[0], 2, accuracy: 0.001)
        XCTAssertEqual(times[1], 6, accuracy: 0.001)
    }
}
