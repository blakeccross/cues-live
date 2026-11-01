import AVFoundation
import XCTest
@testable import CuesLive

final class GainRampTests: XCTestCase {
    private func makeBuffer(frames: Int, channels: Int = 2, value: Float = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: AVAudioChannelCount(channels))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channels {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame] = value
            }
        }
        return buffer
    }

    private func apply(
        _ ramp: inout GainRamp,
        target: Float,
        to buffer: AVAudioPCMBuffer,
        rampFrames: Int
    ) {
        ramp.apply(
            target: target,
            to: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
            frameCount: Int(buffer.frameLength),
            rampFrames: rampFrames
        )
    }

    func testUnityToUnityLeavesSamplesUntouched() {
        var ramp = GainRamp()
        let buffer = makeBuffer(frames: 256, value: 0.5)
        apply(&ramp, target: 1, to: buffer, rampFrames: 64)
        for frame in 0..<256 {
            XCTAssertEqual(buffer.floatChannelData![0][frame], 0.5)
        }
    }

    func testSteadyGainScalesWholeBlock() {
        var ramp = GainRamp(initial: 0.5)
        let buffer = makeBuffer(frames: 256)
        apply(&ramp, target: 0.5, to: buffer, rampFrames: 64)
        for channel in 0..<2 {
            for frame in 0..<256 {
                XCTAssertEqual(buffer.floatChannelData![channel][frame], 0.5, accuracy: 1e-6)
            }
        }
    }

    func testRampsLinearlyThenHoldsTarget() {
        var ramp = GainRamp(initial: 1)
        let buffer = makeBuffer(frames: 256)
        apply(&ramp, target: 0, to: buffer, rampFrames: 64)

        let samples = buffer.floatChannelData![0]
        XCTAssertEqual(samples[0], 1, accuracy: 1e-6)
        XCTAssertEqual(samples[32], 0.5, accuracy: 1e-5)
        for frame in 1..<64 {
            XCTAssertLessThan(samples[frame], samples[frame - 1])
        }
        for frame in 64..<256 {
            XCTAssertEqual(samples[frame], 0)
        }
        XCTAssertEqual(ramp.current, 0)
    }

    func testRampUpStartsFromPreviousGain() {
        var ramp = GainRamp(initial: 0)
        let buffer = makeBuffer(frames: 128)
        apply(&ramp, target: 1, to: buffer, rampFrames: 32)

        let samples = buffer.floatChannelData![1]
        XCTAssertEqual(samples[0], 0)
        XCTAssertEqual(samples[16], 0.5, accuracy: 1e-5)
        XCTAssertEqual(samples[32], 1, accuracy: 1e-6)
        XCTAssertEqual(samples[127], 1, accuracy: 1e-6)
    }

    func testRampLongerThanBlockEndsAtTargetNextBlock() {
        var ramp = GainRamp(initial: 1)
        let buffer = makeBuffer(frames: 16)
        apply(&ramp, target: 0, to: buffer, rampFrames: 480)

        // The ramp is clamped to the block, so it never leaves a half-finished state.
        XCTAssertEqual(ramp.current, 0)
        XCTAssertEqual(buffer.floatChannelData![0][0], 1, accuracy: 1e-6)
        XCTAssertGreaterThan(buffer.floatChannelData![0][15], 0)
        XCTAssertLessThan(buffer.floatChannelData![0][15], 0.1)
    }

    func testSnapSkipsTheRamp() {
        var ramp = GainRamp(initial: 1)
        ramp.snap(to: 0)
        let buffer = makeBuffer(frames: 64)
        apply(&ramp, target: 0, to: buffer, rampFrames: 32)
        for frame in 0..<64 {
            XCTAssertEqual(buffer.floatChannelData![0][frame], 0)
        }
    }
}
