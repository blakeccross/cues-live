import XCTest
@testable import CuesLive

final class SongArrangementLayoutTests: XCTestCase {
    func testPackedRulerSectionsStartAtTimelineZero() {
        let markers = [
            ArrangementMarker(name: "Intro", startSeconds: 30, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 90, sortOrder: 1),
        ]
        let slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()

        let sections = SongArrangementStore.rulerDisplaySections(
            slots: slots,
            markers: markers,
            clipTrims: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 180 }
        )

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].timelineStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(sections[0].sourceStartSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(sections[0].timelineEndSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(sections[1].timelineStartSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(sections[1].sourceStartSeconds, 90, accuracy: 0.001)
    }

    func testAbletonImportPreservesNonZeroFirstMarker() throws {
        let result = AbletonProjectImporter.ImportResult(
            bpm: 120,
            sections: [
                (name: "Intro", startSeconds: 16),
                (name: "Verse", startSeconds: 48),
            ],
            timeSignatures: [
                TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0),
            ]
        )

        let markers = AbletonProjectImporter.makeMarkers(from: result)
        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers[0].name, "Start")
        XCTAssertEqual(markers[0].startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(markers[1].startSeconds, 16, accuracy: 0.001)
        XCTAssertEqual(markers[2].startSeconds, 48, accuracy: 0.001)
    }

    func testAbletonImportPrependsStartSectionForPackedTimeline() {
        let result = AbletonProjectImporter.ImportResult(
            bpm: 120,
            sections: [
                (name: "Verse", startSeconds: 4),
            ],
            timeSignatures: [
                TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0),
            ]
        )
        let markers = AbletonProjectImporter.makeMarkers(from: result)
        let slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()

        let sections = SongArrangementStore.rulerDisplaySections(
            slots: slots,
            markers: markers,
            clipTrims: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].name, "Start")
        XCTAssertEqual(sections[0].timelineStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(sections[0].sourceStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(sections[0].timelineEndSeconds, 4, accuracy: 0.001)
        XCTAssertEqual(sections[1].name, "Verse")
        XCTAssertEqual(sections[1].timelineStartSeconds, 4, accuracy: 0.001)
        XCTAssertEqual(sections[1].sourceStartSeconds, 4, accuracy: 0.001)
    }

    func testIdentityArrangementKeepsContinuousTrackLanes() {
        let markers = [
            ArrangementMarker(name: "INTRO", startSeconds: 8, sortOrder: 0),
            ArrangementMarker(name: "V1", startSeconds: 16, sortOrder: 1),
        ]
        let slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()

        XCTAssertFalse(
            SongArrangementStore.usesSectionedTrackLayout(
                slots: slots,
                markers: markers
            )
        )

        let layout = SongArrangementStore.buildLayoutSnapshot(
            slots: slots,
            clipTrims: [],
            removedClips: [],
            inputs: SongArrangementStore.makeLayoutInputs(
                markers: markers,
                trackIDs: [trackID],
                sourceDurationForTrack: { _ in 120 }
            )
        )

        XCTAssertEqual(layout.rulerSections.count, 2)
        XCTAssertEqual(layout.rulerSections[0].timelineStartSeconds, 8, accuracy: 0.001)
        XCTAssertEqual(layout.rulerSections[1].timelineStartSeconds, 16, accuracy: 0.001)
        XCTAssertTrue(layout.trackSections[trackID]?.isEmpty ?? true)

        let trackSections = SongArrangementStore.trackDisplaySections(
            for: trackID,
            slots: slots,
            markers: markers,
            clipTrims: [],
            removedClips: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 120 }
        )
        XCTAssertTrue(trackSections.isEmpty)
    }

    func testRearrangedArrangementCutsOnlyMovedSection() {
        let markers = [
            ArrangementMarker(name: "A", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "B", startSeconds: 10, sortOrder: 1),
            ArrangementMarker(name: "C", startSeconds: 20, sortOrder: 2),
            ArrangementMarker(name: "D", startSeconds: 30, sortOrder: 3),
        ]
        var slots = SongArrangementStore.defaultSlots(from: markers)
        // Move D to the front: D | A B C
        let moved = slots.removeLast()
        slots.insert(moved, at: 0)
        let trackID = UUID()

        let trackSections = SongArrangementStore.trackDisplaySections(
            for: trackID,
            slots: slots,
            markers: markers,
            clipTrims: [],
            removedClips: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 40 }
        )

        XCTAssertEqual(trackSections.count, 2)
        XCTAssertEqual(trackSections[0].sourceStartSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(trackSections[0].sourceEndSeconds, 40, accuracy: 0.001)
        XCTAssertEqual(trackSections[0].timelineStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].sourceStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].sourceEndSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].timelineStartSeconds, 10, accuracy: 0.001)
    }

    func testRemovedMiddleSectionCutsAroundGap() {
        let markers = [
            ArrangementMarker(name: "A", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "B", startSeconds: 10, sortOrder: 1),
            ArrangementMarker(name: "C", startSeconds: 20, sortOrder: 2),
            ArrangementMarker(name: "D", startSeconds: 30, sortOrder: 3),
        ]
        var slots = SongArrangementStore.defaultSlots(from: markers)
        slots.remove(at: 2) // remove C → A B D
        let trackID = UUID()

        let trackSections = SongArrangementStore.trackDisplaySections(
            for: trackID,
            slots: slots,
            markers: markers,
            clipTrims: [],
            removedClips: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 40 }
        )

        XCTAssertEqual(trackSections.count, 2)
        XCTAssertEqual(trackSections[0].sourceStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(trackSections[0].sourceEndSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].sourceStartSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].sourceEndSeconds, 40, accuracy: 0.001)
    }

    func testDuplicatedSectionCreatesCutAtDuplicate() {
        let markers = [
            ArrangementMarker(name: "A", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "B", startSeconds: 10, sortOrder: 1),
            ArrangementMarker(name: "C", startSeconds: 20, sortOrder: 2),
        ]
        var slots = SongArrangementStore.defaultSlots(from: markers)
        slots.insert(ArrangementSlot(markerID: markers[1].id), at: 2) // A B B' C
        let trackID = UUID()

        let trackSections = SongArrangementStore.trackDisplaySections(
            for: trackID,
            slots: slots,
            markers: markers,
            clipTrims: [],
            removedClips: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 30 }
        )

        XCTAssertEqual(trackSections.count, 2)
        XCTAssertEqual(trackSections[0].sourceStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(trackSections[0].sourceEndSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].sourceStartSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].sourceEndSeconds, 30, accuracy: 0.001)
    }

    func testSwappedAdjacentSectionsStaySeparateClips() {
        let markers = [
            ArrangementMarker(name: "INTRO", startSeconds: 8, sortOrder: 0),
            ArrangementMarker(name: "V1", startSeconds: 16, sortOrder: 1),
        ]
        var slots = SongArrangementStore.defaultSlots(from: markers)
        slots.swapAt(0, 1)
        let trackID = UUID()

        let trackSections = SongArrangementStore.trackDisplaySections(
            for: trackID,
            slots: slots,
            markers: markers,
            clipTrims: [],
            removedClips: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 120 }
        )
        XCTAssertEqual(trackSections.count, 2)
        XCTAssertEqual(trackSections[0].sourceStartSeconds, 16, accuracy: 0.001)
        XCTAssertEqual(trackSections[1].sourceStartSeconds, 8, accuracy: 0.001)
    }

    func testPlaybackSectionsSilenceDeletedGapOnPackedLayout() {
        let markers = [
            ArrangementMarker(name: "INTRO", startSeconds: 0, sortOrder: 0),
        ]
        let slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()
        let inputs = SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        let layout = SongArrangementStore.buildLayoutSnapshot(
            slots: slots,
            clipTrims: [],
            removedClips: [],
            inputs: inputs
        )
        XCTAssertEqual(layout.rulerSections[0].timelineStartSeconds, 0, accuracy: 0.001)

        var regions = [
            ClipRegion(
                id: trackID,
                slotID: slots[0].id,
                trackID: trackID,
                markerID: markers[0].id,
                sourceStartSeconds: 0,
                sourceEndSeconds: 30,
                timelineStartSeconds: 0,
                timelineEndSeconds: 30
            ),
        ]
        _ = ClipRegionStore.deleteTimelineRange(
            slotID: slots[0].id,
            trackID: trackID,
            rangeStart: 10,
            rangeEnd: 20,
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [
                TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0),
            ],
            in: &regions
        )

        let playbackSections = SongArrangementStore.playbackTrackSections(
            for: trackID,
            trimStart: 0,
            trimEnd: 60,
            slots: slots,
            clipTrims: [],
            removedClips: [],
            clipRegions: regions,
            inputs: inputs
        )

        XCTAssertEqual(playbackSections.count, 2)

        let mapper = ArrangementTimelineMapper(
            sections: playbackSections,
            trimStart: 0,
            trimEnd: 60,
            usesArrangement: true
        )

        XCTAssertEqual(mapper.sourceSeconds(atMasterTimeline: 5) ?? -1, 5, accuracy: 0.001)
        XCTAssertNil(mapper.sourceSeconds(atMasterTimeline: 15))
        XCTAssertEqual(mapper.sourceSeconds(atMasterTimeline: 25) ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(
            mapper.regionRemainingSeconds(fromMasterTimeline: 15, bufferLimit: 10),
            5,
            accuracy: 0.001
        )
    }

    func testPlaybackAfterRippleDeleteFromMeasureOne() {
        var markers = [
            ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 40, sortOrder: 1),
        ]
        var slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()
        var clipRegions: [ClipRegion] = []
        var loopSlotIDs: Set<UUID> = []
        var tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        var timeSignatureChanges = [
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0),
        ]
        var midiEvents: [MIDIEvent] = []
        var clipGaps: [ArrangementClipGap] = []

        let tracks = [
            TimelineRippleStore.Track(id: trackID, trimStart: 0, trimEnd: 60, sourceDuration: 60),
        ]

        // Delete measures 1-2 -> removes 4 seconds from the start at 120 BPM in 4/4.
        _ = TimelineRippleStore.rippleDeleteMeasures(
            startMeasure: 1,
            endMeasure: 3,
            markers: &markers,
            slots: &slots,
            clipTrims: [],
            removedClips: [],
            clipGaps: &clipGaps,
            clipRegions: &clipRegions,
            loopSlotIDs: &loopSlotIDs,
            tempoChanges: &tempoChanges,
            timeSignatureChanges: &timeSignatureChanges,
            midiEvents: &midiEvents,
            tracks: tracks,
            defaultBPM: 120,
            defaultNumerator: 4,
            defaultDenominator: 4
        )

        let inputs = SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        let rulerSections = SongArrangementStore.rulerDisplaySections(
            slots: slots,
            markers: markers,
            clipTrims: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        XCTAssertEqual(rulerSections[0].timelineStartSeconds, 0, accuracy: 0.001)

        let playbackSections = SongArrangementStore.playbackTrackSections(
            for: trackID,
            trimStart: 0,
            trimEnd: 60,
            slots: slots,
            clipTrims: [],
            removedClips: [],
            clipRegions: clipRegions,
            inputs: inputs
        )

        XCTAssertFalse(playbackSections.isEmpty)

        let mapper = ArrangementTimelineMapper(
            sections: playbackSections,
            trimStart: 0,
            trimEnd: 60,
            usesArrangement: true
        )

        XCTAssertEqual(mapper.sourceSeconds(atMasterTimeline: 0) ?? -1, 4, accuracy: 0.001)
        XCTAssertTrue(mapper.hasArrangementMapping)
    }

    func testWaveformPeakSectionsUsePlaybackLayoutAfterRipple() {
        var markers = [
            ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 40, sortOrder: 1),
        ]
        var slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()
        var clipRegions: [ClipRegion] = []
        var loopSlotIDs: Set<UUID> = []
        var tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        var timeSignatureChanges = [
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0),
        ]
        var midiEvents: [MIDIEvent] = []
        var clipGaps: [ArrangementClipGap] = []

        _ = TimelineRippleStore.rippleDeleteMeasures(
            startMeasure: 1,
            endMeasure: 3,
            markers: &markers,
            slots: &slots,
            clipTrims: [],
            removedClips: [],
            clipGaps: &clipGaps,
            clipRegions: &clipRegions,
            loopSlotIDs: &loopSlotIDs,
            tempoChanges: &tempoChanges,
            timeSignatureChanges: &timeSignatureChanges,
            midiEvents: &midiEvents,
            tracks: [
                TimelineRippleStore.Track(id: trackID, trimStart: 0, trimEnd: 60, sourceDuration: 60),
            ],
            defaultBPM: 120,
            defaultNumerator: 4,
            defaultDenominator: 4
        )

        let inputs = SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        let rulerSections = SongArrangementStore.rulerDisplaySections(
            slots: slots,
            markers: markers,
            clipTrims: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        let playbackLayout = SongArrangementStore.playbackLayoutSnapshot(
            slots: slots,
            clipTrims: [],
            removedClips: [],
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            tracks: [(trackID, 0, 60)],
            inputs: inputs
        )

        let peakSections = PlaybackCoordinator.waveformPeakSections(
            playbackLayout: playbackLayout,
            rulerSections: rulerSections
        )

        XCTAssertEqual(
            peakSections.map(\.timelineStartSeconds),
            playbackLayout.trackSections[trackID]?.map(\.timelineStartSeconds) ?? []
        )
    }

    func testWaveformPeakSectionsUsePlaybackLayoutForDefaultImport() {
        let markers = [
            ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 40, sortOrder: 1),
        ]
        let slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()
        let inputs = SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        let rulerSections = SongArrangementStore.rulerDisplaySections(
            slots: slots,
            markers: markers,
            clipTrims: [],
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        let playbackLayout = SongArrangementStore.playbackLayoutSnapshot(
            slots: slots,
            clipTrims: [],
            removedClips: [],
            clipGaps: [],
            clipRegions: [],
            tracks: [(trackID, 0, 60)],
            inputs: inputs
        )

        let peakSections = PlaybackCoordinator.waveformPeakSections(
            playbackLayout: playbackLayout,
            rulerSections: rulerSections
        )

        XCTAssertEqual(
            peakSections.map(\.timelineStartSeconds),
            playbackLayout.trackSections[trackID]?.map(\.timelineStartSeconds) ?? []
        )
        XCTAssertEqual(peakSections.first?.timelineStartSeconds ?? -1, 0, accuracy: 0.001)
    }

    func testEffectiveTimelineDurationShortensAfterRippleDelete() {
        var markers = [
            ArrangementMarker(name: "Intro", startSeconds: 0, sortOrder: 0),
            ArrangementMarker(name: "Verse", startSeconds: 40, sortOrder: 1),
        ]
        var slots = SongArrangementStore.defaultSlots(from: markers)
        let trackID = UUID()
        var clipRegions: [ClipRegion] = []
        var loopSlotIDs: Set<UUID> = []
        var tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        var timeSignatureChanges = [
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0),
        ]
        var midiEvents: [MIDIEvent] = []
        var clipGaps: [ArrangementClipGap] = []

        _ = TimelineRippleStore.rippleDeleteMeasures(
            startMeasure: 1,
            endMeasure: 3,
            markers: &markers,
            slots: &slots,
            clipTrims: [],
            removedClips: [],
            clipGaps: &clipGaps,
            clipRegions: &clipRegions,
            loopSlotIDs: &loopSlotIDs,
            tempoChanges: &tempoChanges,
            timeSignatureChanges: &timeSignatureChanges,
            midiEvents: &midiEvents,
            tracks: [
                TimelineRippleStore.Track(id: trackID, trimStart: 0, trimEnd: 60, sourceDuration: 60),
            ],
            defaultBPM: 120,
            defaultNumerator: 4,
            defaultDenominator: 4
        )

        let inputs = SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: [trackID],
            sourceDurationForTrack: { _ in 60 }
        )
        let playbackLayout = SongArrangementStore.playbackLayoutSnapshot(
            slots: slots,
            clipTrims: [],
            removedClips: [],
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            tracks: [(trackID, 0, 60)],
            inputs: inputs
        )

        let duration = SongArrangementStore.effectiveTimelineDuration(
            rulerSections: playbackLayout.rulerSections,
            trackSections: playbackLayout.trackSections
        )
        XCTAssertEqual(duration, 56, accuracy: 0.001)
        XCTAssertEqual(playbackLayout.rulerSections.last?.timelineEndSeconds ?? 0, 56, accuracy: 0.001)

        let playbackSections = SongArrangementStore.playbackTrackSections(
            for: trackID,
            trimStart: 0,
            trimEnd: 60,
            slots: slots,
            clipTrims: [],
            removedClips: [],
            clipRegions: clipRegions,
            inputs: inputs
        )
        let mapper = ArrangementTimelineMapper(
            sections: playbackSections,
            trimStart: 0,
            trimEnd: 60,
            usesArrangement: true
        )
        XCTAssertEqual(mapper.sourceSeconds(atMasterTimeline: 55) ?? -1, 59, accuracy: 0.001)
    }
}

final class SectionRangeInsertionTests: XCTestCase {
    func testDragInsideSectionSplitsHeadAndTail() {
        let verse = ArrangementMarker(name: "Verse", startSeconds: 0, sortOrder: 0)
        let plan = SectionRangeInsertion.plan(
            markers: [verse],
            start: 10,
            end: 20,
            songDuration: 40,
            newSectionName: "Section 1"
        )

        XCTAssertEqual(plan?.markers.map(\.name), ["Verse", "Section 1", "Verse"])
        XCTAssertEqual(plan?.markers.map(\.startSeconds), [0, 10, 20])
        XCTAssertEqual(plan?.markers.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(plan?.sectionMarkerID, plan?.markers[1].id)
        XCTAssertEqual(plan?.markers[0].id, verse.id)
        XCTAssertEqual(plan?.removedMarkerIDs, [])
    }

    func testDragAcrossSectionsKeepsTheNameAtTheEnd() {
        let verse = ArrangementMarker(name: "Verse", startSeconds: 0, sortOrder: 0)
        let chorus = ArrangementMarker(name: "Chorus", startSeconds: 10, sortOrder: 1)
        let bridge = ArrangementMarker(name: "Bridge", startSeconds: 30, sortOrder: 2)
        let plan = SectionRangeInsertion.plan(
            markers: [verse, chorus, bridge],
            start: 5,
            end: 40,
            songDuration: 60,
            newSectionName: "Solo"
        )

        XCTAssertEqual(plan?.markers.map(\.name), ["Verse", "Solo", "Bridge"])
        XCTAssertEqual(plan?.markers.map(\.startSeconds), [0, 5, 40])
        XCTAssertEqual(plan?.sectionMarkerID, plan?.markers[1].id)
        XCTAssertEqual(plan?.removedMarkerIDs, [chorus.id, bridge.id])
        XCTAssertEqual(plan?.markers[0].id, verse.id)
    }

    func testDragEndingOnExistingMarkerDoesNotAddAnother() {
        let verse = ArrangementMarker(name: "Verse", startSeconds: 0, sortOrder: 0)
        let chorus = ArrangementMarker(name: "Chorus", startSeconds: 20, sortOrder: 1)
        let plan = SectionRangeInsertion.plan(
            markers: [verse, chorus],
            start: 5,
            end: 20,
            songDuration: 40,
            newSectionName: "Section 1"
        )

        XCTAssertEqual(plan?.markers.map(\.name), ["Verse", "Section 1", "Chorus"])
        XCTAssertEqual(plan?.markers.map(\.startSeconds), [0, 5, 20])
        XCTAssertEqual(plan?.markers[2].id, chorus.id)
        XCTAssertEqual(plan?.removedMarkerIDs, [])
    }

    func testDragFromExistingMarkerReusesItAndCopiesItsNameForward() {
        let verse = ArrangementMarker(name: "Verse", startSeconds: 0, sortOrder: 0)
        let plan = SectionRangeInsertion.plan(
            markers: [verse],
            start: 0,
            end: 20,
            songDuration: 40,
            newSectionName: "Section 1"
        )

        XCTAssertEqual(plan?.sectionMarkerID, verse.id)
        XCTAssertEqual(plan?.markers.map(\.name), ["Verse", "Verse"])
        XCTAssertEqual(plan?.markers.map(\.startSeconds), [0, 20])
        XCTAssertEqual(plan?.markers[0].id, verse.id)
    }

    func testDragToSongEndDoesNotAddTrailingMarker() {
        let plan = SectionRangeInsertion.plan(
            markers: [],
            start: 10,
            end: 40,
            songDuration: 40,
            newSectionName: "Section 1"
        )

        XCTAssertEqual(plan?.markers.map(\.name), ["Section 1"])
        XCTAssertEqual(plan?.markers.map(\.startSeconds), [10])
    }

    func testDragOnEmptySongBoundsTheSection() {
        let plan = SectionRangeInsertion.plan(
            markers: [],
            start: 10,
            end: 30,
            songDuration: 60,
            newSectionName: "Section 1"
        )

        XCTAssertEqual(plan?.markers.map(\.name), ["Section 1", ""])
        XCTAssertEqual(plan?.markers.map(\.startSeconds), [10, 30])
        XCTAssertEqual(plan?.sectionMarkerID, plan?.markers[0].id)
    }

    func testCollapsedRangeIsRejected() {
        let plan = SectionRangeInsertion.plan(
            markers: [],
            start: 10,
            end: 10.01,
            songDuration: 60,
            newSectionName: "Section 1"
        )
        XCTAssertNil(plan)
    }
}
