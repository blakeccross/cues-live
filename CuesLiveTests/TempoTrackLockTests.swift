import XCTest
@testable import CuesLive

final class TempoTrackLockTests: XCTestCase {
    private let signatures = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]
    private let lockedID = UUID()
    private let unlockedID = UUID()

    private func map(_ changes: [TempoChange]) -> TempoTimeline {
        TempoTimeline(tempoChanges: changes, timeSignatureChanges: signatures)
    }

    private func clip(_ trackID: UUID, start: TimeInterval = 0, duration: TimeInterval) -> TrackClip {
        TrackClip(trackID: trackID, timelineStartSeconds: start, duration: duration, sourceStartSeconds: 0)
    }

    func testHalvingTheSongTempoStretchesLockedTracksOnly() {
        let locked = clip(lockedID, duration: 8)
        let unlocked = clip(unlockedID, duration: 8)
        let timeline = SongTimeline(
            markers: [ArrangementMarker(name: "Chorus", startSeconds: 4)],
            clips: [locked, unlocked]
        )
        let event = MIDIEvent(trackID: UUID(), timelineSeconds: 2, commandID: UUID())

        let result = TempoTrackLock.retime(
            timeline,
            midiEvents: [event],
            lockedTrackIDs: [lockedID],
            from: map([TempoChange(startMeasure: 1, bpm: 120)]),
            to: map([TempoChange(startMeasure: 1, bpm: 60)])
        )

        let lockedClips = result.timeline.clips(forTrack: lockedID)
        XCTAssertEqual(lockedClips.count, 1)
        XCTAssertEqual(lockedClips[0].id, locked.id)
        XCTAssertEqual(lockedClips[0].duration, 16, accuracy: 1e-9)
        XCTAssertEqual(lockedClips[0].playbackRate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(lockedClips[0].sourceDuration, 8, accuracy: 1e-9)
        XCTAssertEqual(result.timeline.clips(forTrack: unlockedID), [unlocked])
        XCTAssertEqual(result.timeline.markers[0].startSeconds, 8, accuracy: 1e-9)
        XCTAssertEqual(result.midiEvents[0].timelineSeconds, 4, accuracy: 1e-9)
    }

    func testMidSongChangeSplitsTheClipAtTheNewTempo() {
        // 120 BPM in 4/4: bar 3 starts at 4 s. Doubling it from there plays the rest twice as fast.
        let locked = clip(lockedID, duration: 10)
        let result = TempoTrackLock.retime(
            SongTimeline(clips: [locked]),
            midiEvents: [],
            lockedTrackIDs: [lockedID],
            from: map([TempoChange(startMeasure: 1, bpm: 120)]),
            to: map([TempoChange(startMeasure: 1, bpm: 120), TempoChange(startMeasure: 3, bpm: 240)])
        )

        let pieces = result.timeline.clips(forTrack: lockedID)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].id, locked.id)
        XCTAssertEqual(pieces[0].timelineEndSeconds, 4, accuracy: 1e-9)
        XCTAssertEqual(pieces[0].playbackRate, 1, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].timelineStartSeconds, 4, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].timelineEndSeconds, 7, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].sourceStartSeconds, 4, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].playbackRate, 2, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].sourceEndSeconds, 10, accuracy: 1e-9)
    }

    func testEveryBeatKeepsItsAudioAfterTheChange() {
        let old = map([TempoChange(startMeasure: 1, bpm: 120), TempoChange(startMeasure: 3, bpm: 90)])
        let new = map([
            TempoChange(startMeasure: 1, bpm: 100),
            TempoChange(startMeasure: 2, beatOffset: 2, bpm: 130),
            TempoChange(startMeasure: 4, bpm: 70)
        ])
        let locked = TrackClip(
            trackID: lockedID,
            timelineStartSeconds: 0.5,
            duration: 12,
            sourceStartSeconds: 3
        )
        let result = TempoTrackLock.retime(
            SongTimeline(clips: [locked]),
            midiEvents: [],
            lockedTrackIDs: [lockedID],
            from: old,
            to: new
        )
        let mapper = ArrangementTimelineMapper(clips: result.timeline.clips, fileDuration: 60)

        for beat in stride(from: 2.0, through: 20, by: 0.5) {
            let tick = beat * Double(TempoChange.ticksPerQuarter)
            let before = locked.sourceTime(atTimeline: old.seconds(atFractionalTick: tick))
            let newTime = new.seconds(atFractionalTick: tick)
            let after = mapper.clip(containing: newTime)?.sourceTime(atTimeline: newTime)
            XCTAssertEqual(after ?? -1, before, accuracy: 1e-6, "beat \(beat)")
        }
    }

    func testScalingEveryTempoKeepsOneClip() {
        let locked = clip(lockedID, duration: 20)
        let result = TempoTrackLock.retime(
            SongTimeline(clips: [locked]),
            midiEvents: [],
            lockedTrackIDs: [lockedID],
            from: map([TempoChange(startMeasure: 1, bpm: 120), TempoChange(startMeasure: 3, bpm: 90)]),
            to: map([TempoChange(startMeasure: 1, bpm: 180), TempoChange(startMeasure: 3, bpm: 135)])
        )

        let pieces = result.timeline.clips(forTrack: lockedID)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].playbackRate, 1.5, accuracy: 1e-9)
    }

    func testNothingLockedLeavesTheArrangementAlone() {
        let timeline = SongTimeline(
            markers: [ArrangementMarker(name: "Verse", startSeconds: 4)],
            clips: [clip(unlockedID, duration: 8)]
        )
        let event = MIDIEvent(trackID: UUID(), timelineSeconds: 2, commandID: UUID())
        let result = TempoTrackLock.retime(
            timeline,
            midiEvents: [event],
            lockedTrackIDs: [],
            from: map([TempoChange(startMeasure: 1, bpm: 120)]),
            to: map([TempoChange(startMeasure: 1, bpm: 60)])
        )

        XCTAssertEqual(result.timeline, timeline)
        XCTAssertEqual(result.midiEvents, [event])
    }
}
