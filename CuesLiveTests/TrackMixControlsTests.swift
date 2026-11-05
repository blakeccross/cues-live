import AVFoundation
import SwiftData
import XCTest
@testable import CuesLive

final class TrackMixReadoutTests: XCTestCase {
    func testVolumeTextShowsDecibels() {
        XCTAssertEqual(TrackMixReadout.volumeText(forGain: 1), "0")
        XCTAssertEqual(TrackMixReadout.volumeText(forGain: MixerFaderScale.linearGain(forDecibels: -10)), "-10")
        XCTAssertEqual(TrackMixReadout.volumeText(forGain: MixerFaderScale.linearGain(forDecibels: 3.5)), "+3.5")
        XCTAssertEqual(TrackMixReadout.volumeText(forGain: MixerFaderScale.linearGain(forDecibels: 6)), "+6")
        XCTAssertEqual(TrackMixReadout.volumeText(forGain: 0), "-inf")
    }

    func testTypedVolumeParsesDecibels() throws {
        let minusTen = try XCTUnwrap(TrackMixReadout.gain(fromVolumeText: "-10"))
        XCTAssertEqual(minusTen, MixerFaderScale.linearGain(forDecibels: -10), accuracy: 1e-9)

        let plusThree = try XCTUnwrap(TrackMixReadout.gain(fromVolumeText: "+3 dB"))
        XCTAssertEqual(plusThree, MixerFaderScale.linearGain(forDecibels: 3), accuracy: 1e-9)

        let unicodeMinus = try XCTUnwrap(TrackMixReadout.gain(fromVolumeText: "−5"))
        XCTAssertEqual(unicodeMinus, MixerFaderScale.linearGain(forDecibels: -5), accuracy: 1e-9)

        XCTAssertEqual(TrackMixReadout.gain(fromVolumeText: "0"), 1)
    }

    func testTypedVolumeCapsAtPlusSixDecibels() throws {
        let capped = try XCTUnwrap(TrackMixReadout.gain(fromVolumeText: "20"))
        XCTAssertEqual(capped, MixerFaderScale.linearGain(forDecibels: 6), accuracy: 1e-9)
    }

    func testTypedVolumeAtOrBelowFloorIsSilent() {
        XCTAssertEqual(TrackMixReadout.gain(fromVolumeText: "-inf"), 0)
        XCTAssertEqual(TrackMixReadout.gain(fromVolumeText: "-60"), 0)
        XCTAssertEqual(TrackMixReadout.gain(fromVolumeText: "-100"), 0)
    }

    func testTypedVolumeRejectsGarbage() {
        XCTAssertNil(TrackMixReadout.gain(fromVolumeText: ""))
        XCTAssertNil(TrackMixReadout.gain(fromVolumeText: "loud"))
    }

    func testPanTextUsesFiftyScale() {
        XCTAssertEqual(TrackMixReadout.panText(forPan: 0), "C")
        XCTAssertEqual(TrackMixReadout.panText(forPan: -1), "-50")
        XCTAssertEqual(TrackMixReadout.panText(forPan: 1), "50")
        XCTAssertEqual(TrackMixReadout.panText(forPan: 0.5), "25")
        XCTAssertEqual(TrackMixReadout.panText(forPan: 0.004), "C")
    }

    func testTypedPanParsesAndClamps() {
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "-50"), -1)
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "50"), 1)
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "25"), 0.5)
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "−25"), -0.5)
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "C"), 0)
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "c"), 0)
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "200"), 1)
        XCTAssertEqual(TrackMixReadout.pan(fromPanText: "-200"), -1)
        XCTAssertNil(TrackMixReadout.pan(fromPanText: "left"))
    }
}

final class TrackPanTests: XCTestCase {
    private func makeBuffer(frames: Int, value: Float = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<2 {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame] = value
            }
        }
        return buffer
    }

    private func apply(_ ramp: inout PanRamp, target: Float, to buffer: AVAudioPCMBuffer, rampFrames: Int) {
        ramp.apply(
            target: target,
            to: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
            frameCount: Int(buffer.frameLength),
            rampFrames: rampFrames
        )
    }

    func testCentreIsUnityOnBothSides() {
        let gains = TrackPan.channelGains(pan: 0)
        XCTAssertEqual(gains.left, 1)
        XCTAssertEqual(gains.right, 1)
    }

    func testPanningAttenuatesOnlyTheFarSide() {
        let right = TrackPan.channelGains(pan: 0.5)
        XCTAssertEqual(right.left, 0.5, accuracy: 1e-6)
        XCTAssertEqual(right.right, 1)

        let left = TrackPan.channelGains(pan: -0.5)
        XCTAssertEqual(left.left, 1)
        XCTAssertEqual(left.right, 0.5, accuracy: 1e-6)
    }

    func testHardPanSilencesOppositeSideAndClampsOutOfRange() {
        XCTAssertEqual(TrackPan.channelGains(pan: -1).right, 0)
        XCTAssertEqual(TrackPan.channelGains(pan: 1).left, 0)
        XCTAssertEqual(TrackPan.channelGains(pan: -5).right, 0)
        XCTAssertEqual(TrackPan.channelGains(pan: 5).left, 0)
    }

    func testCentredRampLeavesSamplesUntouched() {
        var ramp = PanRamp()
        let buffer = makeBuffer(frames: 256, value: 0.5)
        apply(&ramp, target: 0, to: buffer, rampFrames: 64)
        for frame in 0..<256 {
            XCTAssertEqual(buffer.floatChannelData![0][frame], 0.5)
            XCTAssertEqual(buffer.floatChannelData![1][frame], 0.5)
        }
    }

    func testSnappedHardLeftSilencesRightChannel() {
        var ramp = PanRamp()
        ramp.snap(to: -1)
        let buffer = makeBuffer(frames: 256)
        apply(&ramp, target: -1, to: buffer, rampFrames: 64)
        for frame in 0..<256 {
            XCTAssertEqual(buffer.floatChannelData![0][frame], 1)
            XCTAssertEqual(buffer.floatChannelData![1][frame], 0)
        }
    }

    func testPanMoveRampsInsteadOfStepping() {
        var ramp = PanRamp()
        let buffer = makeBuffer(frames: 256)
        apply(&ramp, target: 1, to: buffer, rampFrames: 64)

        let left = buffer.floatChannelData![0]
        XCTAssertEqual(left[0], 1, accuracy: 1e-6)
        XCTAssertGreaterThan(left[1], left[32])
        XCTAssertGreaterThan(left[32], left[63])
        XCTAssertEqual(left[64], 0, accuracy: 1e-6)
        XCTAssertEqual(left[255], 0, accuracy: 1e-6)
        XCTAssertEqual(buffer.floatChannelData![1][255], 1)
        XCTAssertEqual(ramp.current, 1)
    }

    func testMonoOutputIsIgnored() {
        var ramp = PanRamp()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64
        for frame in 0..<64 { buffer.floatChannelData![0][frame] = 1 }

        apply(&ramp, target: 1, to: buffer, rampFrames: 16)
        for frame in 0..<64 {
            XCTAssertEqual(buffer.floatChannelData![0][frame], 1)
        }
    }
}

final class TrackPanBakeTests: XCTestCase {
    private func renderMonoSource(pan: Float, gain: Float = 1) throws -> DecodedStemBuffer {
        let frames = 480
        let source = try DecodedStemBuffer.silent(frameCount: frames, channelCount: 1)
        let samples = source.mutableChannelPointer(0)
        for frame in 0..<frames { samples[frame] = 1 }

        let output = try DecodedStemBuffer.silent(frameCount: frames, channelCount: 2)
        let mapper = ArrangementTimelineMapper(
            sections: [],
            trimStart: 0,
            trimEnd: Double(frames) / source.sampleRate,
            usesArrangement: false
        )
        GroupStemOfflineRenderer.mix(source: source, into: output, mapper: mapper, gain: gain, pan: pan)
        return output
    }

    func testCentredMonoSourceFeedsBothChannelsAtUnity() throws {
        let output = try renderMonoSource(pan: 0)
        XCTAssertEqual(output.channelPointer(0)[100], 1, accuracy: 1e-6)
        XCTAssertEqual(output.channelPointer(1)[100], 1, accuracy: 1e-6)
    }

    func testHardRightMonoSourceSilencesLeft() throws {
        let output = try renderMonoSource(pan: 1)
        XCTAssertEqual(output.channelPointer(0)[100], 0, accuracy: 1e-6)
        XCTAssertEqual(output.channelPointer(1)[100], 1, accuracy: 1e-6)
    }

    func testPanComposesWithGain() throws {
        let output = try renderMonoSource(pan: 0.5, gain: 0.5)
        XCTAssertEqual(output.channelPointer(0)[100], 0.25, accuracy: 1e-6)
        XCTAssertEqual(output.channelPointer(1)[100], 0.5, accuracy: 1e-6)
    }
}

final class TrackPanPersistenceTests: XCTestCase {
    func testProjectTrackMixRoundTripsPan() throws {
        let track = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        track.pan = -0.4

        let data = try JSONEncoder().encode(ProjectTrackMix(from: track))
        let decoded = try JSONDecoder().decode(ProjectTrackMix.self, from: data)
        XCTAssertEqual(decoded.pan, -0.4)

        let target = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        decoded.apply(to: target)
        XCTAssertEqual(target.pan, -0.4)
    }

    func testProjectTrackMixWithoutPanDecodesAsCentred() throws {
        let legacy = """
        {"volume":0.5,"isMuted":false,"isSolo":true,"trimStartSeconds":1.5,"excludeFromTranspose":false}
        """
        let decoded = try JSONDecoder().decode(ProjectTrackMix.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.pan, 0)
        XCTAssertEqual(decoded.volume, 0.5)
        XCTAssertEqual(decoded.trimStartSeconds, 1.5)
        XCTAssertTrue(decoded.isSolo)
    }

    func testNewTrackIsCentredAndSettingsCarryPan() {
        let track = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        XCTAssertEqual(track.pan, 0)
        XCTAssertEqual(AudioEngineManager.TrackSettings(track: track).pan, 0)

        track.pan = 0.25
        XCTAssertEqual(AudioEngineManager.TrackSettings(track: track).pan, 0.25)
    }

    func testEditSnapshotRoundTripsPan() throws {
        let schema = Schema(PersistenceController.modelTypes)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let song = Song(name: "Pan Test")
        let track = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        track.pan = 0.6
        track.song = song
        song.tracks = [track]
        context.insert(song)

        let snapshot = SongEditSnapshot.capture(
            song: song,
            markers: [],
            arrangementSlots: [],
            clipTrims: [],
            removedClips: [],
            clipGaps: [],
            clipRegions: [],
            loopSlotIDs: [],
            tempoChanges: [],
            timeSignatureChanges: [],
            midiEvents: []
        )
        XCTAssertEqual(snapshot.tracks.first?.pan, 0.6)

        track.pan = -1
        snapshot.applyTracks(to: song, context: context)
        XCTAssertEqual(song.sortedTracks.first?.pan, 0.6)
    }
}

final class TrackPanFingerprintTests: XCTestCase {
    private func fingerprint(for song: Song) -> String {
        let projectState = SongProjectBridge.ProjectState(
            markers: [],
            arrangement: SongArrangementStore.defaultArrangement(for: []),
            tempoChanges: SongProjectBridge.defaultTempoChanges(for: song),
            timeSignatureChanges: SongProjectBridge.defaultTimeSignatureChanges(for: song),
            midiEvents: []
        )
        return SongBakeFingerprint.compute(for: song, projectState: projectState)
    }

    func testFingerprintChangesWhenTrackPanChanges() {
        let song = Song(name: "Bake Test")
        let track = AudioTrack(displayName: "Kick", relativeFilePath: "kick.wav", sortOrder: 0)
        song.tracks = [track]

        let centred = fingerprint(for: song)
        track.pan = 0.5
        let panned = fingerprint(for: song)
        track.pan = 0
        let recentred = fingerprint(for: song)

        XCTAssertNotEqual(centred, panned)
        XCTAssertEqual(centred, recentred)
    }
}
