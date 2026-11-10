import XCTest
@testable import CuesLive

final class ClipEditingTests: XCTestCase {
    private let drums = UUID()
    private let bass = UUID()

    /// Two stems recorded from zero: drums 60 s, bass 50 s. Sections A [0, 20), B [20, 40), C [40, 60).
    private func makeTimeline() -> SongTimeline {
        SongTimeline(
            markers: [
                ArrangementMarker(name: "A", startSeconds: 0),
                ArrangementMarker(name: "B", startSeconds: 20),
                ArrangementMarker(name: "C", startSeconds: 40),
            ],
            clips: [
                TrackClip(trackID: drums, timelineStartSeconds: 0, duration: 60, sourceStartSeconds: 0),
                TrackClip(trackID: bass, timelineStartSeconds: 0, duration: 50, sourceStartSeconds: 0),
            ]
        )
    }

    private func source(_ timeline: SongTimeline, _ trackID: UUID, at time: TimeInterval) -> TimeInterval? {
        timeline.clips(forTrack: trackID).first { $0.containsTimelineTime(time) }?.sourceTime(atTimeline: time)
    }

    // MARK: - Single-clip edits

    func testSplitKeepsSourceContinuity() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)

        let rightID = try XCTUnwrap(ClipEditing.split(clipID: clipID, at: 25, in: &timeline.clips))

        let right = try XCTUnwrap(timeline.clips.first { $0.id == rightID })
        XCTAssertEqual(right.timelineStartSeconds, 25)
        XCTAssertEqual(right.sourceStartSeconds, 25)
        XCTAssertEqual(right.duration, 35)
        XCTAssertEqual(timeline.clips(forTrack: drums).first?.duration, 25)
    }

    func testTrimExtendsAcrossSectionBoundaries() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: bass).first?.id)
        ClipEditing.trim(clipID: clipID, edge: .trailing, to: 30, sourceDuration: 50, in: &timeline.clips)

        let trimmed = try XCTUnwrap(
            ClipEditing.trim(clipID: clipID, edge: .trailing, to: 45, sourceDuration: 50, in: &timeline.clips)
        )
        XCTAssertEqual(trimmed.timelineEndSeconds, 45, accuracy: 1e-9, "runs past the marker at 40")
    }

    func testTrailingTrimOverrunsAndCutsBackTheNextClip() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: clipID, at: 30, in: &timeline.clips))
        ClipEditing.trim(clipID: clipID, edge: .trailing, to: 20, sourceDuration: 60, in: &timeline.clips)

        let left = try XCTUnwrap(
            ClipEditing.trim(clipID: clipID, edge: .trailing, to: 45, sourceDuration: 60, in: &timeline.clips)
        )

        XCTAssertEqual(left.timelineEndSeconds, 45, accuracy: 1e-9)
        let right = try XCTUnwrap(timeline.clips.first { $0.id == rightID })
        XCTAssertEqual(right.timelineStartSeconds, 45, accuracy: 1e-9, "the overrun clip is cut back")
        XCTAssertEqual(right.sourceStartSeconds, 45, accuracy: 1e-9)
        XCTAssertEqual(timeline.clips(forTrack: drums).count, 2)
    }

    func testLeadingTrimOverrunsThePreviousClip() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: clipID, at: 30, in: &timeline.clips))
        ClipEditing.trim(clipID: rightID, edge: .leading, to: 35, sourceDuration: 60, in: &timeline.clips)

        ClipEditing.trim(clipID: rightID, edge: .leading, to: 10, sourceDuration: 60, in: &timeline.clips)

        let left = try XCTUnwrap(timeline.clips.first { $0.id == clipID })
        XCTAssertEqual(left.timelineEndSeconds, 10, accuracy: 1e-9)
        XCTAssertEqual(source(timeline, drums, at: 12), 12)
    }

    func testTrimSwallowsAClipItFullyCovers() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        let middleID = try XCTUnwrap(ClipEditing.split(clipID: clipID, at: 20, in: &timeline.clips))
        let lastID = try XCTUnwrap(ClipEditing.split(clipID: middleID, at: 25, in: &timeline.clips))
        ClipEditing.trim(clipID: clipID, edge: .trailing, to: 15, sourceDuration: 60, in: &timeline.clips)

        ClipEditing.trim(clipID: clipID, edge: .trailing, to: 30, sourceDuration: 60, in: &timeline.clips)

        XCTAssertNil(timeline.clips.first { $0.id == middleID })
        XCTAssertEqual(timeline.clips.first { $0.id == lastID }?.timelineStartSeconds ?? 0, 30, accuracy: 1e-9)
    }

    func testTrailingTrimStopsAtTheEndOfTheFile() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)

        let trimmed = try XCTUnwrap(
            ClipEditing.trim(clipID: clipID, edge: .trailing, to: 90, sourceDuration: 60, in: &timeline.clips)
        )
        XCTAssertEqual(trimmed.timelineEndSeconds, 60, accuracy: 1e-9)
    }

    func testTrimmingTwoSelectedClipsStopsAtEachOther() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: clipID, at: 30, in: &timeline.clips))
        ClipEditing.trim(clipID: clipID, edge: .trailing, to: 20, sourceDuration: 60, in: &timeline.clips)

        ClipEditing.trim(clipIDs: [clipID, rightID], edge: .trailing, by: 20, sourceDuration: { _ in 60 }, in: &timeline.clips)

        let left = try XCTUnwrap(timeline.clips.first { $0.id == clipID })
        let right = try XCTUnwrap(timeline.clips.first { $0.id == rightID })
        XCTAssertEqual(left.timelineEndSeconds, 30, accuracy: 1e-9, "stops at the selected clip after it")
        XCTAssertEqual(right.timelineStartSeconds, 30, accuracy: 1e-9)
        XCTAssertEqual(right.timelineEndSeconds, 60, accuracy: 1e-9)
    }

    func testLeadingTrimCannotPassFileStart() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: bass).first?.id)
        ClipEditing.move(clipIDs: [clipID], by: 10, in: &timeline.clips)

        let trimmed = try XCTUnwrap(
            ClipEditing.trim(clipID: clipID, edge: .leading, to: 2, sourceDuration: 50, in: &timeline.clips)
        )
        XCTAssertEqual(trimmed.timelineStartSeconds, 10, accuracy: 1e-9)
        XCTAssertEqual(trimmed.sourceStartSeconds, 0, accuracy: 1e-9)
    }

    func testMoveCutsBackTheClipItLandsOn() throws {
        var timeline = makeTimeline()
        let drumClip = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: drumClip, at: 40, in: &timeline.clips))

        ClipEditing.move(clipIDs: [rightID], by: 0, toTrack: bass, in: &timeline.clips)

        let bassClips = timeline.clips(forTrack: bass)
        XCTAssertEqual(bassClips.map(\.timelineStartSeconds), [0, 40])
        XCTAssertEqual(bassClips.map(\.timelineEndSeconds), [40, 60])
        XCTAssertEqual(source(timeline, bass, at: 45), 45)
    }

    func testMoveIsClampedAtZero() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: bass).first?.id)

        ClipEditing.move(clipIDs: [clipID], by: -5, in: &timeline.clips)

        XCTAssertEqual(timeline.clips(forTrack: bass).first?.timelineStartSeconds, 0)
    }

    func testTrailingTrimIgnoresAnUnknownFileLength() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)

        let longer = try XCTUnwrap(
            ClipEditing.trim(clipID: clipID, edge: .trailing, to: 90, sourceDuration: 0, in: &timeline.clips)
        )
        XCTAssertEqual(longer.timelineEndSeconds, 90, accuracy: 1e-9)

        let shortest = try XCTUnwrap(
            ClipEditing.trim(clipID: clipID, edge: .trailing, to: -5, sourceDuration: 0, in: &timeline.clips)
        )
        XCTAssertEqual(shortest.duration, TrackClip.minimumDuration, accuracy: 1e-9)
    }

    func testMovingClipsFromTwoTracksOntoOneTrackDoesNotOverlap() throws {
        var timeline = makeTimeline()
        let drumClip = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        let bassClip = try XCTUnwrap(timeline.clips(forTrack: bass).first?.id)
        ClipEditing.move(clipIDs: [bassClip], by: 10, in: &timeline.clips)
        let target = UUID()

        ClipEditing.move(clipIDs: [drumClip, bassClip], by: 0, toTrack: target, in: &timeline.clips)

        let moved = timeline.clips(forTrack: target)
        XCTAssertEqual(moved.map(\.timelineStartSeconds), [0, 10])
        XCTAssertEqual(moved.map(\.timelineEndSeconds), [10, 60], "the later clip wins where they overlap")
    }

    func testInsertSpaceDropsALeadingSliverInsteadOfStraddlingTheGap() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []

        ClipEditing.insertSpace(at: 0.05, length: 4, timeline: &timeline, midiEvents: &midi)

        let drumClips = timeline.clips(forTrack: drums)
        XCTAssertEqual(drumClips.count, 1)
        XCTAssertEqual(drumClips[0].timelineStartSeconds, 4.05, accuracy: 1e-9)
        XCTAssertEqual(drumClips[0].sourceStartSeconds, 0.05, accuracy: 1e-9)
    }

    func testInsertSpaceDropsATrailingSliverInsteadOfStraddlingTheGap() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []

        ClipEditing.insertSpace(at: 59.95, length: 4, timeline: &timeline, midiEvents: &midi)

        let drumClips = timeline.clips(forTrack: drums)
        XCTAssertEqual(drumClips.count, 1)
        XCTAssertEqual(drumClips[0].timelineEndSeconds, 59.95, accuracy: 1e-9)
    }

    func testJoinHealsGapWhenSourceIsContinuous() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        ClipEditing.split(clipID: clipID, at: 20, in: &timeline.clips)
        ClipEditing.deleteRange(trackIDs: [drums], from: 10, to: 30, in: &timeline.clips)
        XCTAssertNil(source(timeline, drums, at: 15))

        XCTAssertEqual(ClipEditing.joinWithNext(clipID: clipID, in: &timeline.clips), clipID)

        XCTAssertEqual(timeline.clips(forTrack: drums).count, 1)
        XCTAssertEqual(source(timeline, drums, at: 15), 15)
    }

    func testJoinRefusesDiscontinuousSource() throws {
        var timeline = makeTimeline()
        let clipID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: clipID, at: 30, in: &timeline.clips))
        ClipEditing.trim(clipID: rightID, edge: .leading, to: 35, sourceDuration: 60, in: &timeline.clips)
        ClipEditing.move(clipIDs: [rightID], by: -5, in: &timeline.clips)

        XCTAssertNil(ClipEditing.joinWithNext(clipID: clipID, in: &timeline.clips))
    }

    // MARK: - Whole-song edits

    func testRippleDeleteShiftsClipsMarkersAndMIDI() {
        var timeline = makeTimeline()
        let midiTrack = UUID()
        var midi = [
            MIDIEvent(trackID: midiTrack, timelineSeconds: 25, commandID: UUID()),
            MIDIEvent(trackID: midiTrack, timelineSeconds: 45, commandID: UUID()),
        ]

        ClipEditing.rippleDelete(from: 20, to: 40, timeline: &timeline, midiEvents: &midi)

        XCTAssertEqual(timeline.sortedMarkers.map(\.name), ["A", "C"])
        XCTAssertEqual(timeline.sortedMarkers.map(\.startSeconds), [0, 20])
        XCTAssertEqual(source(timeline, drums, at: 19), 19)
        XCTAssertEqual(source(timeline, drums, at: 21), 41)
        XCTAssertEqual(timeline.clips(forTrack: bass).last?.timelineEndSeconds, 30)
        XCTAssertEqual(midi.map(\.timelineSeconds), [25])
    }

    func testRippleDeleteKeepsNameOfSectionCutInHalf() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []
        let sectionB = timeline.markers[1].id

        ClipEditing.rippleDelete(from: 10, to: 30, timeline: &timeline, midiEvents: &midi)

        XCTAssertEqual(timeline.sortedMarkers.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(timeline.sortedMarkers.map(\.startSeconds), [0, 10, 20])
        XCTAssertEqual(timeline.sortedMarkers[1].id, sectionB)
    }

    func testRemovingLastSectionLeavesNoStrayMarker() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []

        ClipEditing.removeSection(timeline.markers[2].id, timeline: &timeline, midiEvents: &midi)

        XCTAssertEqual(timeline.sortedMarkers.map(\.name), ["A", "B"])
        XCTAssertEqual(timeline.contentEnd, 40)
    }

    func testDuplicateSectionInsertsCopyAfterIt() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []
        let originalIDs = timeline.sortedMarkers.map(\.id)

        ClipEditing.duplicateSection(originalIDs[1], timeline: &timeline, midiEvents: &midi)

        let sections = timeline.sections()
        XCTAssertEqual(sections.map(\.name), ["A", "B", "B", "C"])
        XCTAssertEqual(sections.map(\.timelineStartSeconds), [0, 20, 40, 60])
        XCTAssertEqual(sections[1].id, originalIDs[1])
        XCTAssertEqual(sections[3].id, originalIDs[2])
        XCTAssertNotEqual(sections[2].id, originalIDs[1])
        XCTAssertEqual(source(timeline, drums, at: 45), 25)
        XCTAssertEqual(source(timeline, drums, at: 65), 45)
        XCTAssertEqual(source(timeline, bass, at: 65), 45)
        XCTAssertNil(source(timeline, bass, at: 75))
    }

    func testDuplicateMidSectionRangeKeepsNamesOnBothSides() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []

        ClipEditing.duplicateRange(
            from: 25,
            to: 30,
            insertingAt: 45,
            timeline: &timeline,
            midiEvents: &midi
        )

        XCTAssertEqual(timeline.sortedMarkers.map(\.name), ["A", "B", "C", "B", "C"])
        XCTAssertEqual(timeline.sortedMarkers.map(\.startSeconds), [0, 20, 40, 45, 50])
        XCTAssertEqual(source(timeline, drums, at: 47), 27)
        XCTAssertEqual(source(timeline, drums, at: 52), 47)
    }

    func testMoveSectionToFrontKeepsIDsAndLoopFlag() {
        var timeline = makeTimeline()
        timeline.markers[2].loops = true
        var midi: [MIDIEvent] = []
        let ids = timeline.sortedMarkers.map(\.id)

        ClipEditing.moveSection(ids[2], toIndex: 0, timeline: &timeline, midiEvents: &midi)

        let sections = timeline.sections()
        XCTAssertEqual(sections.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(sections.map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertEqual(sections.map(\.timelineStartSeconds), [0, 20, 40])
        XCTAssertTrue(sections[0].loops)
        XCTAssertEqual(source(timeline, drums, at: 5), 45)
        XCTAssertEqual(source(timeline, drums, at: 25), 5)
        XCTAssertEqual(source(timeline, bass, at: 5), 45)
        XCTAssertNil(source(timeline, bass, at: 15))
    }

    func testMoveSectionToEnd() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []
        let ids = timeline.sortedMarkers.map(\.id)

        ClipEditing.moveSection(ids[0], toIndex: 3, timeline: &timeline, midiEvents: &midi)

        let sections = timeline.sections()
        XCTAssertEqual(sections.map(\.id), [ids[1], ids[2], ids[0]])
        XCTAssertEqual(source(timeline, drums, at: 45), 5)
        XCTAssertEqual(Set(timeline.markers.map(\.id)).count, timeline.markers.count)
    }

    func testMovingLastSectionDoesNotDuplicateMarkerIDs() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []
        let ids = timeline.sortedMarkers.map(\.id)

        ClipEditing.moveSection(ids[2], toIndex: 1, timeline: &timeline, midiEvents: &midi)

        XCTAssertEqual(timeline.sections().map(\.id), [ids[0], ids[2], ids[1]])
        XCTAssertEqual(timeline.markers.count, 3)
    }

    func testInsertSpaceSplitsAndShifts() {
        var timeline = makeTimeline()
        var midi: [MIDIEvent] = []

        ClipEditing.insertSpace(at: 30, length: 4, timeline: &timeline, midiEvents: &midi)

        XCTAssertNil(source(timeline, drums, at: 32))
        XCTAssertEqual(source(timeline, drums, at: 35), 31)
        XCTAssertEqual(timeline.sortedMarkers.map(\.startSeconds), [0, 20, 44])
    }

    func testSectionsAreDerivedFromMarkers() {
        let timeline = makeTimeline()
        let sections = timeline.sections()

        XCTAssertEqual(sections.map(\.timelineStartSeconds), [0, 20, 40])
        XCTAssertEqual(sections.map(\.timelineEndSeconds), [20, 40, 60])
        XCTAssertEqual(sections.section(atTimeline: 25)?.name, "B")
    }

    // MARK: - Selection

    func testPressSelectsOnlyAnUnselectedClip() {
        let a = UUID(), b = UUID()
        var selection = ClipSelection([a])
        selection.press(b, extending: false)
        XCTAssertEqual(selection.clipIDs, [b])
    }

    func testPressOnSelectedClipKeepsSelectionForGroupDrag() {
        let a = UUID(), b = UUID()
        var selection = ClipSelection([a, b])
        XCTAssertFalse(selection.press(a, extending: false))
        XCTAssertEqual(selection.clipIDs, [a, b])
    }

    func testShiftPressAddsOrDefersRemoval() {
        let a = UUID(), b = UUID()
        var selection = ClipSelection([a])
        XCTAssertFalse(selection.press(b, extending: true))
        XCTAssertEqual(selection.clipIDs, [a, b])
        XCTAssertTrue(selection.press(a, extending: true), "removal waits for a click without drag")
        XCTAssertEqual(selection.clipIDs, [a, b])
    }

    func testClipCursorMatchesTheZoneUnderThePointer() {
        let width: CGFloat = 200
        XCTAssertEqual(
            ClipPointerCursor.zone(at: CGPoint(x: 4, y: 8), clipWidth: width, laneHeight: 104),
            .trim
        )
        XCTAssertEqual(
            ClipPointerCursor.zone(at: CGPoint(x: 190, y: 8), clipWidth: width, laneHeight: 104),
            .trim
        )
        XCTAssertEqual(
            ClipPointerCursor.zone(at: CGPoint(x: 40, y: 8), clipWidth: width, laneHeight: 104),
            .select
        )
        XCTAssertEqual(
            ClipPointerCursor.zone(at: CGPoint(x: 40, y: 40), clipWidth: width, laneHeight: 104),
            .select
        )
        XCTAssertEqual(
            ClipPointerCursor.zone(at: CGPoint(x: 4, y: 80), clipWidth: width, laneHeight: 104),
            .move
        )
        XCTAssertEqual(
            ClipPointerCursor.zone(at: CGPoint(x: 100, y: 52), clipWidth: width, laneHeight: 104),
            .move
        )
        XCTAssertEqual(
            ClipPointerCursor.zone(at: CGPoint(x: 2, y: 4), clipWidth: 20, laneHeight: 104),
            .select,
            "a clip too narrow for trim handles selects from the header"
        )
    }

    func testMeasureLinesStopAtClipHeaders() {
        let headers = [CGRect(x: 10, y: 0, width: 80, height: 16), CGRect(x: 40, y: 104, width: 30, height: 16)]
        let gaps = MeasureGridSpans.gaps(at: 50, in: headers)
        XCTAssertEqual(
            MeasureGridSpans.verticalSegments(from: 0, to: 208, skipping: gaps).map { [$0.0, $0.1] },
            [[16, 104], [120, 208]]
        )
        XCTAssertEqual(
            MeasureGridSpans.verticalSegments(from: 0, to: 208, skipping: MeasureGridSpans.gaps(at: 5, in: headers)).map { [$0.0, $0.1] },
            [[0, 208]]
        )
    }

    func testDragRangeSelectsClipsTheRangeOverlaps() throws {
        var timeline = makeTimeline()
        let drumsClip = try XCTUnwrap(timeline.clips(forTrack: drums).first)
        let right = try XCTUnwrap(ClipEditing.split(clipID: drumsClip.id, at: 30, in: &timeline.clips))
        let bassClip = try XCTUnwrap(timeline.clips(forTrack: bass).first?.id)

        let hits = ClipSelection.clipIDs(in: timeline.clips, trackIDs: [drums], from: 35, to: 36)
        XCTAssertEqual(hits, [right])

        let across = ClipSelection.clipIDs(in: timeline.clips, trackIDs: [drums], from: 60, to: 20)
        XCTAssertEqual(across, [drumsClip.id, right])

        let otherTrack = ClipSelection.clipIDs(in: timeline.clips, trackIDs: [bass], from: 0, to: 10)
        XCTAssertEqual(otherTrack, [bassClip])

        let point = ClipSelection.clipIDs(in: timeline.clips, trackIDs: [drums, bass], from: 12, to: 12)
        XCTAssertTrue(point.isEmpty)
    }

    // MARK: - Selection edits

    func testCopyLeavesOriginalsAndSelectsCopies() throws {
        var timeline = makeTimeline()
        let drumsClip = try XCTUnwrap(timeline.clips(forTrack: drums).first)
        ClipEditing.trim(clipID: drumsClip.id, edge: .trailing, to: 10, sourceDuration: 60, in: &timeline.clips)

        let copies = ClipEditing.copy(clipIDs: [drumsClip.id], by: 20, in: &timeline.clips)

        let drumClips = timeline.clips(forTrack: drums)
        XCTAssertEqual(drumClips.count, 2)
        XCTAssertEqual(copies.count, 1)
        XCTAssertTrue(drumClips.contains { $0.id == drumsClip.id && $0.timelineStartSeconds == 0 })
        XCTAssertEqual(source(timeline, drums, at: 25), 5)
    }

    func testDuplicatePlacesCopiesAfterTheSelectedSpan() throws {
        var timeline = makeTimeline()
        for clip in timeline.clips {
            ClipEditing.trim(clipID: clip.id, edge: .trailing, to: 10, sourceDuration: 60, in: &timeline.clips)
        }
        let ids = Set(timeline.clips.map(\.id))

        let copies = ClipEditing.duplicate(clipIDs: ids, in: &timeline.clips)

        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(source(timeline, drums, at: 12), 2)
        XCTAssertEqual(source(timeline, bass, at: 12), 2)
    }

    func testTrimSelectionMovesTheSameEdgeOnEveryClip() {
        var timeline = makeTimeline()
        let ids = Set(timeline.clips.map(\.id))

        ClipEditing.trim(clipIDs: ids, edge: .trailing, by: -5, sourceDuration: { _ in 60 }, in: &timeline.clips)

        XCTAssertEqual(timeline.clips(forTrack: drums).first?.timelineEndSeconds ?? 0, 55, accuracy: 1e-9)
        XCTAssertEqual(timeline.clips(forTrack: bass).first?.timelineEndSeconds ?? 0, 45, accuracy: 1e-9)
    }

    func testSplitSelectionCutsEveryClipThatSpansTheTime() {
        var timeline = makeTimeline()
        let ids = Set(timeline.clips.map(\.id))

        let rightIDs = ClipEditing.split(clipIDs: ids, at: 30, in: &timeline.clips)

        XCTAssertEqual(rightIDs.count, 2)
        XCTAssertEqual(timeline.clips.count, 4)
        XCTAssertEqual(source(timeline, bass, at: 31), 31)
    }

    func testJoinSelectionMergesAdjacentSelectedClips() throws {
        var timeline = makeTimeline()
        let drumsClip = try XCTUnwrap(timeline.clips(forTrack: drums).first)
        let middle = try XCTUnwrap(ClipEditing.split(clipID: drumsClip.id, at: 20, in: &timeline.clips))
        let last = try XCTUnwrap(ClipEditing.split(clipID: middle, at: 40, in: &timeline.clips))

        let remaining = ClipEditing.join(clipIDs: [drumsClip.id, middle, last], in: &timeline.clips)

        XCTAssertEqual(remaining, [drumsClip.id])
        XCTAssertEqual(timeline.clips(forTrack: drums).count, 1)
        XCTAssertEqual(timeline.clips(forTrack: drums).first?.duration ?? 0, 60, accuracy: 1e-9)
    }

    func testTrackClickSelectsOnlyThatTrack() {
        let tracks = [UUID(), UUID(), UUID()]
        let selected = TrackSelection.click(
            id: tracks[1],
            in: [tracks[0], tracks[2]],
            order: tracks,
            modifiers: PointerModifiers()
        )
        XCTAssertEqual(selected, [tracks[1]])
    }

    func testCommandClickTogglesOneTrack() {
        let tracks = [UUID(), UUID(), UUID()]
        let added = TrackSelection.click(
            id: tracks[2],
            in: [tracks[0]],
            order: tracks,
            modifiers: PointerModifiers(command: true)
        )
        XCTAssertEqual(added, [tracks[0], tracks[2]])

        let removed = TrackSelection.click(
            id: tracks[0],
            in: added,
            order: tracks,
            modifiers: PointerModifiers(command: true)
        )
        XCTAssertEqual(removed, [tracks[2]])
    }

    func testShiftClickExtendsToTheNearestSelectedTrack() {
        let tracks = [UUID(), UUID(), UUID(), UUID(), UUID()]
        let selected = TrackSelection.click(
            id: tracks[2],
            in: [tracks[0], tracks[4]],
            order: tracks,
            modifiers: PointerModifiers(shift: true)
        )
        XCTAssertEqual(selected, [tracks[0], tracks[1], tracks[2], tracks[4]])
    }

    // MARK: - Clip gain

    func testClipGainTaperRoundTripsAndClamps() {
        XCTAssertEqual(ClipGain.decibels(forPosition: 0), -144, accuracy: 0.01)
        XCTAssertEqual(ClipGain.decibels(forPosition: 1), 36, accuracy: 0.01)
        XCTAssertEqual(ClipGain.decibels(forPosition: .nan), -144, accuracy: 0.01)
        XCTAssertEqual(ClipGain.position(forDecibels: .infinity), 0, accuracy: 0.000_1)
        for decibels in stride(from: -144.0, through: 36, by: 6) {
            let roundTrip = ClipGain.decibels(forPosition: ClipGain.position(forDecibels: decibels))
            XCTAssertEqual(roundTrip, decibels, accuracy: 0.01, "\(decibels)")
        }
        XCTAssertEqual(ClipGain.stored(400), 36)
        XCTAssertEqual(ClipGain.stored(-200), -144)
        XCTAssertEqual(ClipGain.stored(.nan), 0)
        XCTAssertEqual(ClipGain.linearGain(decibels: 0), 1)
        XCTAssertEqual(ClipGain.linearGain(decibels: -144), 0)
        XCTAssertEqual(Double(ClipGain.linearGain(decibels: 6.020599913279624)), 2, accuracy: 0.001)
        XCTAssertEqual(ClipGain.lineY(decibels: 0, bodyHeight: 80), 40, accuracy: 0.001)
    }

    func testSetGainClampsAndLeavesOtherClips() throws {
        var timeline = makeTimeline()
        let drumsID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        ClipEditing.setGain(clipIDs: [drumsID], decibels: 80, in: &timeline.clips)
        XCTAssertEqual(timeline.clips(forTrack: drums)[0].gainDB, 36)
        XCTAssertEqual(timeline.clips(forTrack: bass)[0].gainDB, 0)

        ClipEditing.nudgeGain(clipIDs: [drumsID], by: 1, in: &timeline.clips)
        XCTAssertEqual(timeline.clips(forTrack: drums)[0].gainDB, 36)
        ClipEditing.setGain(clipIDs: [drumsID], decibels: 3, in: &timeline.clips)
        ClipEditing.nudgeGain(clipIDs: [drumsID], by: -1, in: &timeline.clips)
        XCTAssertEqual(timeline.clips(forTrack: drums)[0].gainDB, 2)
    }

    func testSplitAndCopyKeepClipGain() throws {
        var timeline = makeTimeline()
        let drumsID = try XCTUnwrap(timeline.clips(forTrack: drums).first?.id)
        ClipEditing.setGain(clipIDs: [drumsID], decibels: -6, in: &timeline.clips)
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: drumsID, at: 20, in: &timeline.clips))
        XCTAssertEqual(timeline.clips.first { $0.id == drumsID }?.gainDB, -6)
        XCTAssertEqual(timeline.clips.first { $0.id == rightID }?.gainDB, -6)

        let copies = ClipEditing.copy(clipIDs: [drumsID], by: 20, in: &timeline.clips)
        let copy = try XCTUnwrap(copies.first)
        XCTAssertEqual(timeline.clips.first { $0.id == copy }?.gainDB, -6)
    }

    func testMissingGainDecodesAsUnity() throws {
        let clip = TrackClip(trackID: drums, timelineStartSeconds: 0, duration: 4, sourceStartSeconds: 1, gainDB: -3)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any]
        var legacy = try XCTUnwrap(encoded)
        legacy.removeValue(forKey: "gainDB")
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(TrackClip.self, from: data)
        XCTAssertEqual(decoded.gainDB, 0)
        XCTAssertEqual(decoded.sourceStartSeconds, 1)

        let stored = try JSONDecoder().decode(TrackClip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(stored.gainDB, -3)
    }

    func testPlacedFileStartsWhereItWasDropped() {
        let clip = TrackClip.placed(trackID: drums, sourceDuration: 10, timelineStart: 4)
        XCTAssertEqual(clip?.timelineStartSeconds, 4)
        XCTAssertEqual(clip?.duration, 10)
        XCTAssertEqual(clip?.sourceStartSeconds, 0)
    }

    func testPlacedFileKeepsItsTrimAndWillNotStartBeforeZero() {
        let clip = TrackClip.placed(
            trackID: drums,
            sourceDuration: 10,
            trimStart: 1,
            trimEnd: 6,
            timelineStart: -3
        )
        XCTAssertEqual(clip?.timelineStartSeconds, 0)
        XCTAssertEqual(clip?.sourceStartSeconds, 1)
        XCTAssertEqual(clip?.duration, 5)
        XCTAssertNil(TrackClip.placed(trackID: drums, sourceDuration: 10, trimStart: 9.95, trimEnd: 10))
    }

    func testAudioDropAcceptsAudioAndRefusesOtherFiles() {
        XCTAssertTrue(FileStore.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/kick.wav")))
        XCTAssertTrue(FileStore.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/room.aif")))
        XCTAssertTrue(FileStore.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/click.m4a")))
        XCTAssertFalse(FileStore.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/session.scraft")))
        XCTAssertFalse(FileStore.isSupportedAudioFile(URL(fileURLWithPath: "/tmp/notes.txt")))
    }
}
