import AVFoundation
import XCTest
@testable import CuesLive

final class OutputTestSignalBuilderTests: XCTestCase {
    private let sampleRate: Double = 48_000

    func testPinkNoiseFadesInAndEndsInSilence() throws {
        let noise = try XCTUnwrap(
            OutputTestSignalBuilder.pinkNoise(sampleRate: sampleRate, duration: 1, fade: 0.02, trailingSilence: 0.5)
        )
        let samples = try XCTUnwrap(noise.floatChannelData?[0])

        XCTAssertEqual(Int(noise.frameLength), 72_000)
        XCTAssertEqual(samples[0], 0)
        XCTAssertTrue((48_000..<72_000).allSatisfy { samples[$0] == 0 })
        XCTAssertTrue((0..<48_000).contains { samples[$0] != 0 })
        XCTAssertTrue((0..<48_000).allSatisfy { abs(samples[$0]) <= 1 })
    }

    func testLayersLandOnlyOnTheirDestinationChannels() throws {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 4))
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: false,
            channelLayout: layout
        )
        let short = try makeConstantMono(value: 0.25, frames: 100)
        let long = try makeConstantMono(value: 0.5, frames: 200)

        let buffer = try XCTUnwrap(OutputTestSignalBuilder.multiChannelBuffer(
            [
                OutputTestSignalBuilder.Layer(mono: short, destination: .stereoPair(startChannel: 1)),
                OutputTestSignalBuilder.Layer(mono: long, destination: .mono(channel: 4))
            ],
            format: format
        ))
        let channels = try XCTUnwrap(buffer.floatChannelData)

        XCTAssertEqual(buffer.frameLength, 200)
        XCTAssertEqual(channels[0][50], 0.25)
        XCTAssertEqual(channels[1][50], 0.25)
        XCTAssertEqual(channels[1][150], 0)
        XCTAssertEqual(channels[2][50], 0)
        XCTAssertEqual(channels[3][150], 0.5)
    }

    func testOverlappingLayersSumAndClip() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let loud = try makeConstantMono(value: 0.75, frames: 10)

        let buffer = try XCTUnwrap(OutputTestSignalBuilder.multiChannelBuffer(
            [
                OutputTestSignalBuilder.Layer(mono: loud, destination: .mono(channel: 1)),
                OutputTestSignalBuilder.Layer(mono: loud, destination: .stereoPair(startChannel: 1))
            ],
            format: format
        ))
        let channels = try XCTUnwrap(buffer.floatChannelData)

        XCTAssertEqual(channels[0][0], 1)
        XCTAssertEqual(channels[1][0], 0.75)
    }

    private func makeConstantMono(value: Float, frames: Int) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        samples.update(repeating: value, count: frames)
        return buffer
    }
}
