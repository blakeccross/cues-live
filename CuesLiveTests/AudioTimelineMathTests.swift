import XCTest
@testable import CuesLive

final class AudioTimelineMathTests: XCTestCase {
    func testQuantizeSnapsToNearestSampleBoundary() {
        let sampleRate = 48_000.0
        let oneSample = 1.0 / sampleRate

        // 2.5 samples should round away from zero to 3 samples.
        let input = oneSample * 2.5
        let expected = oneSample * 3.0

        XCTAssertEqual(
            AudioTimelineMath.quantize(input, sampleRate: sampleRate),
            expected,
            accuracy: 0.0000001
        )
    }

    func testQuantizeReturnsInputWhenSampleRateIsNonPositive() {
        let input: TimeInterval = 1.234
        XCTAssertEqual(AudioTimelineMath.quantize(input, sampleRate: 0), input, accuracy: 0.000001)
        XCTAssertEqual(AudioTimelineMath.quantize(input, sampleRate: -48000), input, accuracy: 0.000001)
    }
}

final class TrackLaneHeightTests: XCTestCase {
    func testDefaultHeightIsMedium() {
        XCTAssertEqual(TimelineLayout.laneHeight, TrackLaneHeight.medium)
        XCTAssertEqual(TrackLaneHeight.storedDefault, Double(TrackLaneHeight.medium))
        let audio = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        let midi = MIDITrack(displayName: "Keys", sortOrder: 0)
        XCTAssertEqual(audio.laneHeight, TrackLaneHeight.storedDefault)
        XCTAssertEqual(midi.laneHeight, TrackLaneHeight.storedDefault)
        XCTAssertEqual(TrackLaneHeight.resolved(0), TrackLaneHeight.medium)
        XCTAssertEqual(TrackLaneHeight.resolved(1_000), TrackLaneHeight.medium)
    }

    func testDragSnapsToPresetsAndCommandDragIsFree() {
        let start = TrackLaneHeight.medium
        XCTAssertEqual(TrackLaneHeight.snapped(start + 20), TrackLaneHeight.medium)
        XCTAssertEqual(TrackLaneHeight.snapped(start + 44), TrackLaneHeight.large)
        XCTAssertEqual(TrackLaneHeight.snapped(start + 132), TrackLaneHeight.jumbo)
        XCTAssertEqual(TrackLaneHeight.snapped(start + 40), TrackLaneHeight.large)
        XCTAssertEqual(TrackLaneHeight.snapped(20), TrackLaneHeight.micro)
        XCTAssertEqual(TrackLaneHeight.free(start + 20), 108)
        XCTAssertEqual(TrackLaneHeight.free(4), TrackLaneHeight.micro)
        XCTAssertEqual(TrackLaneHeight.free(900), TrackLaneHeight.extreme)
    }

    func testStepMovesOnePreset() {
        XCTAssertEqual(TrackLaneHeight.step(TrackLaneHeight.medium, taller: true), TrackLaneHeight.large)
        XCTAssertEqual(TrackLaneHeight.step(TrackLaneHeight.medium, taller: false), TrackLaneHeight.small)
        XCTAssertEqual(TrackLaneHeight.step(100, taller: true), TrackLaneHeight.large)
        XCTAssertEqual(TrackLaneHeight.step(100, taller: false), TrackLaneHeight.medium)
        XCTAssertEqual(TrackLaneHeight.step(TrackLaneHeight.micro, taller: false), TrackLaneHeight.micro)
        XCTAssertEqual(TrackLaneHeight.step(TrackLaneHeight.extreme, taller: true), TrackLaneHeight.extreme)
    }

    func testResizeTargets() {
        let tracks = [UUID(), UUID(), UUID(), UUID()]
        let dragged = tracks[0]
        let selected: Set<UUID> = [tracks[2], tracks[3]]

        XCTAssertEqual(
            TrackLaneHeight.targets(owned: [dragged], shown: tracks, selected: selected, option: false, shift: false),
            [dragged]
        )
        XCTAssertEqual(
            TrackLaneHeight.targets(owned: [dragged], shown: tracks, selected: selected, option: true, shift: false),
            tracks
        )
        XCTAssertEqual(
            TrackLaneHeight.targets(owned: [dragged], shown: tracks, selected: selected, option: true, shift: true),
            [dragged, tracks[2], tracks[3]]
        )
        XCTAssertEqual(
            TrackLaneHeight.targets(owned: selected, shown: tracks, selected: selected, option: false, shift: false),
            [tracks[2], tracks[3]]
        )
        XCTAssertEqual(
            TrackLaneHeight.targets(owned: [], shown: tracks, selected: [], option: true, shift: false),
            tracks
        )
    }

    func testLaneFramesPlaceRowsOfDifferentHeights() {
        let frames = TrackLaneFrames(heights: [88, 46, 132])
        XCTAssertEqual(frames.totalHeight, 266)
        XCTAssertEqual(frames.rows.map(\.originY), [0, 88, 134])
        XCTAssertEqual(frames.rowIndex(at: 0), 0)
        XCTAssertEqual(frames.rowIndex(at: 87), 0)
        XCTAssertEqual(frames.rowIndex(at: 88), 1)
        XCTAssertEqual(frames.rowIndex(at: 133), 1)
        XCTAssertEqual(frames.rowIndex(at: 134), 2)
        XCTAssertEqual(frames.rowIndex(at: 1_000), 2)
        XCTAssertEqual(frames.rowIndex(at: -10), 0)
        XCTAssertEqual(TrackLaneFrames(heights: []).totalHeight, 0)
    }
}

