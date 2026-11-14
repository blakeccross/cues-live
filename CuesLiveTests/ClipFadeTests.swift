import XCTest
@testable import CuesLive

final class ClipFadeTests: XCTestCase {
    private let drums = UUID()

    private func makeClip(
        start: TimeInterval = 0,
        duration: TimeInterval = 10,
        fadeIn: ClipFade = .none,
        fadeOut: ClipFade = .none
    ) -> TrackClip {
        TrackClip(
            trackID: drums,
            timelineStartSeconds: start,
            duration: duration,
            sourceStartSeconds: 0,
            fadeIn: fadeIn,
            fadeOut: fadeOut
        )
    }

    func testEveryShapeRunsFromSilenceToUnity() {
        for shape in ClipFadeShape.allCases {
            XCTAssertEqual(shape.gain(at: 0), 0, accuracy: 1e-9, "\(shape)")
            XCTAssertEqual(shape.gain(at: 1), 1, accuracy: 1e-9, "\(shape)")
            XCTAssertEqual(shape.gain(at: -3), 0, accuracy: 1e-9, "\(shape)")
            XCTAssertEqual(shape.gain(at: 3), 1, accuracy: 1e-9, "\(shape)")
            XCTAssertEqual(shape.gain(at: .nan), 0, "\(shape)")
        }
        XCTAssertEqual(ClipFadeShape.linear.gain(at: 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ClipFadeShape.equalPower.gain(at: 0.5), 0.5.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(ClipFadeShape.sCurve.gain(at: 0.5), 0.5, accuracy: 1e-9)
    }

    func testCurvatureBendsTheMiddleAndKeepsTheEndsAndTheOrder() {
        for shape in ClipFadeShape.allCases {
            let plain = ClipFade(duration: 1, shape: shape)
            for curvature in [-1.0, -0.5, 0, 0.5, 1] {
                let fade = plain.with(curvature: curvature)
                XCTAssertEqual(fade.gain(at: 0), 0)
                XCTAssertEqual(fade.gain(at: 1), 1, accuracy: 1e-9)
                var previous = 0.0
                for step in 0...128 {
                    let gain = fade.gain(at: Double(step) / 128)
                    XCTAssertGreaterThanOrEqual(gain, previous, "\(shape) \(curvature)")
                    previous = gain
                }
                XCTAssertEqual(fade.curvature(forMidpointGain: fade.gain(at: 0.5)), curvature, accuracy: 1e-6)
            }
            XCTAssertGreaterThan(plain.with(curvature: 0.5).gain(at: 0.5), plain.gain(at: 0.5))
            XCTAssertLessThan(plain.with(curvature: -0.5).gain(at: 0.5), plain.gain(at: 0.5))
        }
    }

    func testUnusableValuesAreReplaced() {
        XCTAssertEqual(ClipFade(duration: -2, shape: .linear, curvature: 0.4), .none)
        XCTAssertEqual(ClipFade(duration: .nan), .none)
        XCTAssertEqual(ClipFade(duration: 1, curvature: 9).curvature, 1)
        XCTAssertEqual(ClipFade(duration: 1, curvature: .infinity).curvature, 0)
        XCTAssertEqual(ClipFade(duration: 1).curvature(forMidpointGain: .nan), 0, accuracy: 1e-9)
    }

    func testClipsSavedBeforeFadesDecodeWithoutThem() throws {
        let json = """
        {"id":"\(UUID().uuidString)","trackID":"\(drums.uuidString)",
         "timelineStartSeconds":2,"duration":4,"sourceStartSeconds":1,"gainDB":0,"playbackRate":1}
        """
        let clip = try JSONDecoder().decode(TrackClip.self, from: Data(json.utf8))
        XCTAssertEqual(clip.fadeIn, .none)
        XCTAssertEqual(clip.fadeOut, .none)
        XCTAssertFalse(clip.hasFades)
    }

    func testFadesRoundTripAndAnUnknownShapeStillDecodes() throws {
        let clip = makeClip(
            fadeIn: ClipFade(duration: 2, shape: .equalPower, curvature: 0.25),
            fadeOut: ClipFade(duration: 3, shape: .logarithmic, curvature: -0.5)
        )
        let data = try JSONEncoder().encode(clip)
        XCTAssertEqual(try JSONDecoder().decode(TrackClip.self, from: data), clip)

        let future = Data(#"{"duration":1.5,"shape":"fromALaterVersion","curvature":0.2}"#.utf8)
        let fade = try JSONDecoder().decode(ClipFade.self, from: future)
        XCTAssertEqual(fade, ClipFade(duration: 1.5, shape: .sCurve, curvature: 0.2))
    }

    func testFadeGainFollowsBothFades() {
        let clip = makeClip(
            fadeIn: ClipFade(duration: 2, shape: .linear),
            fadeOut: ClipFade(duration: 4, shape: .linear)
        )
        XCTAssertEqual(clip.fadeGain(atOffset: 0), 0)
        XCTAssertEqual(clip.fadeGain(atOffset: 1), 0.5, accuracy: 1e-6)
        XCTAssertEqual(clip.fadeGain(atOffset: 2), 1)
        XCTAssertEqual(clip.fadeGain(atOffset: 5), 1)
        XCTAssertEqual(clip.fadeGain(atOffset: 8), 0.5, accuracy: 1e-6)
        XCTAssertEqual(clip.fadeGain(atOffset: 10), 0)
        XCTAssertEqual(clip.fadeGain(atOffset: -0.1), 0)
        XCTAssertEqual(clip.fadeGain(atOffset: 10.1), 0)
    }

    func testOverlappingFadesMultiply() {
        let full = ClipFade(duration: 10, shape: .linear)
        let clip = makeClip(fadeIn: full, fadeOut: full)
        XCTAssertEqual(clip.fadeGain(atOffset: 5), 0.25, accuracy: 1e-6)
    }

    func testFadesNeverOutlastTheClip() {
        var clip = makeClip(fadeIn: ClipFade(duration: 30), fadeOut: ClipFade(duration: 4))
        XCTAssertEqual(clip.fadeIn.duration, 10)
        clip.duration = 3
        XCTAssertEqual(clip.fadeIn.duration, 3)
        XCTAssertEqual(clip.fadeOut.duration, 3)
        clip.fadeOut = ClipFade(duration: 8, shape: .linear)
        XCTAssertEqual(clip.fadeOut, ClipFade(duration: 3, shape: .linear))
    }

    func testDraggingAHandleSetsTheLengthFromThatEnd() {
        let clip = makeClip(start: 4, fadeOut: ClipFade(duration: 1, shape: .linear, curvature: 0.3))
        XCTAssertEqual(ClipEditing.fade(clip, edge: .leading, draggedTo: 6.5), ClipFade(duration: 2.5))
        XCTAssertEqual(
            ClipEditing.fade(clip, edge: .trailing, draggedTo: 11),
            ClipFade(duration: 3, shape: .linear, curvature: 0.3)
        )
        XCTAssertEqual(ClipEditing.fade(clip, edge: .leading, draggedTo: 99).duration, 10)
        XCTAssertEqual(ClipEditing.fade(clip, edge: .leading, draggedTo: 1), .none)
        XCTAssertEqual(ClipEditing.fade(clip, edge: .trailing, draggedTo: 99), .none)
    }

    func testSplitKeepsTheOuterFadesAndTheCutHasNone() throws {
        let fadeIn = ClipFade(duration: 2)
        let fadeOut = ClipFade(duration: 3, shape: .linear)
        var clips = [makeClip(fadeIn: fadeIn, fadeOut: fadeOut)]
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: clips[0].id, at: 5, in: &clips))
        let left = try XCTUnwrap(clips.first { $0.id != rightID })
        let right = try XCTUnwrap(clips.first { $0.id == rightID })
        XCTAssertEqual(left.fadeIn, fadeIn)
        XCTAssertEqual(left.fadeOut, .none)
        XCTAssertEqual(right.fadeIn, .none)
        XCTAssertEqual(right.fadeOut, fadeOut)
    }

    func testJoinFadesInLikeTheFirstClipAndOutLikeTheSecond() throws {
        let fadeIn = ClipFade(duration: 2)
        let fadeOut = ClipFade(duration: 3, shape: .linear)
        var clips = [makeClip(fadeIn: fadeIn, fadeOut: fadeOut)]
        let leftID = clips[0].id
        let rightID = try XCTUnwrap(ClipEditing.split(clipID: leftID, at: 5, in: &clips))
        ClipEditing.setFade(ClipFade(duration: 1), edge: .trailing, clipID: leftID, in: &clips)
        ClipEditing.setFade(ClipFade(duration: 1), edge: .leading, clipID: rightID, in: &clips)

        XCTAssertEqual(ClipEditing.joinWithNext(clipID: leftID, in: &clips), leftID)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips[0].fadeIn, fadeIn)
        XCTAssertEqual(clips[0].fadeOut, fadeOut)
    }

    func testTrimAndMoveAndCopyKeepFades() throws {
        let fadeIn = ClipFade(duration: 2)
        let fadeOut = ClipFade(duration: 6, shape: .linear)
        var clips = [makeClip(fadeIn: fadeIn, fadeOut: fadeOut)]
        let id = clips[0].id

        ClipEditing.move(clipIDs: [id], by: 5, in: &clips)
        XCTAssertEqual(clips[0].fadeIn, fadeIn)
        XCTAssertEqual(clips[0].fadeOut, fadeOut)

        let copyID = try XCTUnwrap(ClipEditing.copy(clipIDs: [id], by: 20, in: &clips).first)
        let copy = try XCTUnwrap(clips.first { $0.id == copyID })
        XCTAssertEqual(copy.fadeIn, fadeIn)
        XCTAssertEqual(copy.fadeOut, fadeOut)

        let trimmed = try XCTUnwrap(
            ClipEditing.trim(clipID: id, edge: .trailing, to: 9, sourceDuration: 10, in: &clips)
        )
        XCTAssertEqual(trimmed.duration, 4, accuracy: 1e-9)
        XCTAssertEqual(trimmed.fadeIn, fadeIn)
        XCTAssertEqual(trimmed.fadeOut, ClipFade(duration: 4, shape: .linear))
    }

    func testAClipCutBackByAnotherLosesTheFadeAtTheCut() throws {
        var clips = [makeClip(fadeIn: ClipFade(duration: 2), fadeOut: ClipFade(duration: 2))]
        ClipEditing.carve(trackID: drums, from: 8, to: 12, in: &clips)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips[0].fadeIn, ClipFade(duration: 2))
        XCTAssertEqual(clips[0].fadeOut, .none)
    }

    func testFadeShapeAndRemovalActOnTheListedClips() {
        var clips = [
            makeClip(fadeIn: ClipFade(duration: 2, curvature: 0.5)),
            makeClip(start: 20, fadeOut: ClipFade(duration: 2)),
        ]
        ClipEditing.setFadeShape(.equalPower, clipIDs: [clips[0].id], in: &clips)
        XCTAssertEqual(clips[0].fadeIn, ClipFade(duration: 2, shape: .equalPower))
        XCTAssertEqual(clips[0].fadeOut, .none)
        XCTAssertEqual(clips[1].fadeOut, ClipFade(duration: 2))

        ClipEditing.removeFades(clipIDs: [clips[1].id], in: &clips)
        XCTAssertTrue(clips[0].hasFades)
        XCTAssertFalse(clips[1].hasFades)
    }

    func testAFadeDragPreviewsOnItsClipOnly() {
        let clips = [makeClip(), makeClip(start: 20)]
        let fade = ClipFade(duration: 3)
        let preview = ClipDrag.fade(clipID: clips[1].id, edge: .trailing, fade: fade)
            .applied(to: clips, clipIDs: [], sourceDuration: { _ in 10 })
        XCTAssertEqual(preview[0], clips[0])
        XCTAssertEqual(preview[1].fadeOut, fade)
    }

    func testTempoLockedClipKeepsItsFadesInBeats() throws {
        let signatures = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]
        let old = TempoTimeline(tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)], timeSignatureChanges: signatures)
        let new = TempoTimeline(tempoChanges: [TempoChange(startMeasure: 1, bpm: 60)], timeSignatureChanges: signatures)
        let clip = makeClip(fadeIn: ClipFade(duration: 2), fadeOut: ClipFade(duration: 1, shape: .linear))
        let result = TempoTrackLock.retime(
            SongTimeline(markers: [], clips: [clip]),
            midiEvents: [],
            lockedTrackIDs: [drums],
            from: old,
            to: new
        )
        let retimed = try XCTUnwrap(result.timeline.clips.first)
        XCTAssertEqual(retimed.duration, 20, accuracy: 1e-6)
        XCTAssertEqual(retimed.fadeIn.duration, 4, accuracy: 1e-6)
        XCTAssertEqual(retimed.fadeOut.duration, 2, accuracy: 1e-6)
        XCTAssertEqual(retimed.fadeOut.shape, .linear)
    }
}
