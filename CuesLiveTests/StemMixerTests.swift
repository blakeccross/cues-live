import AVFoundation
import XCTest
@testable import CuesLive

final class StemMixerTests: XCTestCase {
    /// Writes `level` to every channel and records the host time of each call.
    private final class ConstantVoice: MixerVoice {
        let level: Float
        let isSilent: Bool
        private(set) var hostTimes: [UInt64] = []
        private(set) var frameCounts: [AVAudioFrameCount] = []

        init(level: Float, isSilent: Bool = false) {
            self.level = level
            self.isSilent = isSilent
        }

        func render(
            frameCount: AVAudioFrameCount,
            hostTime: UInt64,
            outputBuffer: UnsafeMutablePointer<AudioBufferList>
        ) -> Bool {
            hostTimes.append(hostTime)
            frameCounts.append(frameCount)
            for buffer in UnsafeMutableAudioBufferListPointer(outputBuffer) {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) { data[frame] = isSilent ? 0 : level }
            }
            return !isSilent
        }
    }

    private let blockFrames = 512

    func testVoiceOnTheDefaultRoutePlaysAtFullLevelOnBothOutputs() {
        let mixer = StemMixer()
        let voice = ConstantVoice(level: 0.5)
        mixer.setEntries([entry(voice, .defaultDestination, outputs: 2)])

        let output = render(mixer, outputs: 2)

        XCTAssertEqual(output[0][100], 0.5)
        XCTAssertEqual(output[1][100], 0.5)
    }

    func testVoicesOnTheSameOutputsAreSummed() {
        let mixer = StemMixer()
        mixer.setEntries([
            entry(ConstantVoice(level: 0.25), .defaultDestination, outputs: 2),
            entry(ConstantVoice(level: 0.5), .defaultDestination, outputs: 2)
        ])

        let output = render(mixer, outputs: 2)

        XCTAssertEqual(output[0][0], 0.75)
        XCTAssertEqual(output[1][blockFrames - 1], 0.75)
    }

    func testEachVoiceLandsOnlyOnItsRoutedOutputs() {
        let mixer = StemMixer()
        mixer.setEntries([
            entry(ConstantVoice(level: 0.5), .stereoPair(startChannel: 3), outputs: 6),
            entry(ConstantVoice(level: 0.25), .mono(channel: 6), outputs: 6)
        ])

        let output = render(mixer, outputs: 6)

        XCTAssertEqual(output.map { $0[10] }, [0, 0, 0.5, 0.5, 0, 0.25])
    }

    func testNoOutputStillRendersTheVoiceButAddsNothing() {
        let mixer = StemMixer()
        let voice = ConstantVoice(level: 0.5)
        mixer.setEntries([entry(voice, .none, outputs: 2)])

        let output = render(mixer, outputs: 2)

        XCTAssertEqual(voice.hostTimes.count, 1, "keeps meters and streaming moving")
        XCTAssertEqual(output.flatMap { $0 }.max(), 0)
    }

    func testOutputIsClearedBeforeMixing() {
        let mixer = StemMixer()
        mixer.setEntries([entry(ConstantVoice(level: 0, isSilent: true), .defaultDestination, outputs: 2)])

        let output = render(mixer, outputs: 2, prefill: 0.9)

        XCTAssertEqual(output.flatMap { $0 }.max(), 0)
    }

    func testLongRequestIsSplitWithTheHostTimeAdvancedForEachPart() {
        let mixer = StemMixer()
        let voice = ConstantVoice(level: 0.5)
        mixer.setEntries([entry(voice, .defaultDestination, outputs: 2)])
        let frames = StemMixer.maximumBusFrames + 100

        let output = render(mixer, outputs: 2, frames: frames, hostTime: 1_000)

        XCTAssertEqual(voice.frameCounts, [AVAudioFrameCount(StemMixer.maximumBusFrames), 100])
        XCTAssertEqual(voice.hostTimes.first, 1_000)
        let expectedGap = hostTicks(seconds: Double(StemMixer.maximumBusFrames) / DecodedStemBuffer.engineSampleRate)
        XCTAssertEqual(Double(voice.hostTimes[1] - 1_000), Double(expectedGap), accuracy: 2)
        XCTAssertEqual(output[1][frames - 1], 0.5, "the second part lands after the first")
    }

    func testMonoTrackPannedHardRightPlaysOnlyOnTheRight() throws {
        let transport = AudioPlaybackTransport()
        transport.setDuration(1)
        let player = try makeMonoPlayer(level: 0.5, transport: transport)
        player.updateMix(volume: 1, pan: 1, isAudible: true)
        let mixer = StemMixer()
        mixer.setEntries([StemMixer.Entry(
            voice: player.mixerVoice,
            route: MixerRoute(destination: .defaultDestination, outputChannelCount: 2)
        )])
        transport.beginPlayback(from: 0)

        let output = render(mixer, outputs: 2, hostTime: hostTicks(seconds: 100))

        XCTAssertEqual(output[0][100], 0, accuracy: 0.000_1)
        XCTAssertEqual(output[1][100], 0.5, accuracy: 0.000_1, "a mono stem plays at full level")
    }

    // MARK: - Fixtures

    private func entry(_ voice: any MixerVoice, _ destination: OutputDestination, outputs: Int) -> StemMixer.Entry {
        StemMixer.Entry(voice: voice, route: MixerRoute(destination: destination, outputChannelCount: outputs))
    }

    private func render(
        _ mixer: StemMixer,
        outputs: Int,
        frames: Int? = nil,
        hostTime: UInt64 = 0,
        prefill: Float = 0
    ) -> [[Float]] {
        let frameCount = frames ?? blockFrames
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: outputs * frameCount)
        samples.initialize(repeating: prefill, count: outputs * frameCount)
        defer { samples.deallocate() }
        let list = AudioBufferList.allocate(maximumBuffers: outputs)
        defer { free(list.unsafeMutablePointer) }
        for channel in 0..<outputs {
            list[channel] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(frameCount * MemoryLayout<Float>.size),
                mData: samples + channel * frameCount
            )
        }
        mixer.render(frameCount: AVAudioFrameCount(frameCount), hostTime: hostTime, into: list.unsafeMutablePointer)
        return (0..<outputs).map { Array(UnsafeBufferPointer(start: samples + $0 * frameCount, count: frameCount)) }
    }

    private func makeMonoPlayer(level: Float, transport: AudioPlaybackTransport) throws -> TrackMemoryPlayer {
        let sampleRate = DecodedStemBuffer.engineSampleRate
        let frames = Int(sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = level }
        return TrackMemoryPlayer(
            trackID: UUID(),
            buffer: try DecodedStemBuffer.monoStem(from: pcm),
            transport: transport,
            mapper: ArrangementTimelineMapper.linear(trimStart: 0, trimEnd: 1)
        )
    }

    private func hostTicks(seconds: TimeInterval) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return UInt64(seconds * 1_000_000_000 * Double(info.denom) / Double(info.numer))
    }
}
