import AVFoundation
import XCTest
@testable import CuesLive

final class LiveStretcherTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let blockFrames = 512

    private func makeSource(seconds: Double, sample: (Int) -> Float) throws -> DecodedStemBuffer {
        let buffer = try DecodedStemBuffer.silent(frameCount: Int(seconds * sampleRate), sampleRate: sampleRate)
        buffer.withMutableSamples(channel: 0) { samples, count in
            for frame in 0..<count { samples[frame] = sample(frame) }
        }
        return buffer
    }

    /// Renders `frames` frames block by block. `segment` gives each block's source position and rate.
    private func render(
        _ stretcher: LiveStretcher,
        source: DecodedStemBuffer,
        frames: Int,
        semitones: Float = 0,
        timelineSlip: (Int) -> Int = { _ in 0 },
        segment: (Int) -> (sourceSeconds: Double, rate: Double)
    ) -> [Float] {
        var output = [Float](repeating: 0, count: frames)
        var block = [Float](repeating: 0, count: blockFrames)
        var start = 0
        while start < frames {
            let count = min(blockFrames, frames - start)
            let timelineFrame = start + timelineSlip(start / blockFrames)
            let position = segment(timelineFrame)
            block.withUnsafeMutableBufferPointer { samples in
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(count * MemoryLayout<Float>.size),
                        mData: UnsafeMutableRawPointer(samples.baseAddress)
                    )
                )
                stretcher.render(
                    source: source,
                    timelineFrame: timelineFrame,
                    sourceSeconds: position.sourceSeconds,
                    rate: position.rate,
                    semitones: semitones,
                    frameCount: count,
                    into: UnsafeMutableAudioBufferListPointer(&list),
                    outputOffset: 0,
                    gain: 1
                )
            }
            output.replaceSubrange(start..<(start + count), with: block[0..<count])
            start += count
        }
        return output
    }

    private func magnitude(of samples: ArraySlice<Float>, frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        var real = 0.0
        var imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            real += Double(sample) * cos(omega * Double(index))
            imaginary -= Double(sample) * sin(omega * Double(index))
        }
        return (real * real + imaginary * imaginary).squareRoot()
    }

    private func peak(in output: [Float], near frame: Int) -> Int {
        let window = max(0, frame - 960)..<min(output.count, frame + 960)
        return window.max { abs(output[$0]) < abs(output[$1]) } ?? -1
    }

    private func clickTrain(seconds: Double) throws -> DecodedStemBuffer {
        try makeSource(seconds: seconds) { frame in
            let into = frame % 24_000
            return into < 48 ? 1 - Float(into) / 48 : 0
        }
    }

    func testKeyChangeRaisesThePitchAnOctave() throws {
        let source = try makeSource(seconds: 2) { sinf(2 * .pi * 440 * Float($0) / 48_000) * 0.5 }
        let stretcher = try XCTUnwrap(LiveStretcher(channelCount: 1, sampleRate: sampleRate))

        let output = render(stretcher, source: source, frames: 48_000, semitones: 12) { frame in
            (Double(frame) / 48_000, 1)
        }

        let steady = output[9_600..<48_000]
        XCTAssertGreaterThan(magnitude(of: steady, frequency: 880), magnitude(of: steady, frequency: 440) * 4)
    }

    func testClockSlipBetweenBlocksKeepsTheToneClean() throws {
        // The transport clock follows host time, so a block can start a frame or two away
        // from where the last one ended. That must not restart the stretcher.
        let source = try makeSource(seconds: 3) { sinf(2 * .pi * 440 * Float($0) / 48_000) * 0.5 }
        let stretcher = try XCTUnwrap(LiveStretcher(channelCount: 1, sampleRate: sampleRate))
        let slips = [0, 1, 1, 2, 1, 3, 2, 2]

        let output = render(
            stretcher,
            source: source,
            frames: 96_000,
            semitones: 2,
            timelineSlip: { slips[$0 % slips.count] },
            segment: { frame in (Double(frame) / 48_000, 1) }
        )

        // A restart splices the tone at a random phase and steps the waveform. An unbroken
        // 494 Hz tone at half scale never moves more than 0.033 between samples.
        let steady = output[9_600..<96_000]
        let steepestStep = zip(steady, steady.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(steepestStep, 0.05)
    }

    func testFasterClipKeepsItsPitch() throws {
        let source = try makeSource(seconds: 4) { sinf(2 * .pi * 440 * Float($0) / 48_000) * 0.5 }
        let stretcher = try XCTUnwrap(LiveStretcher(channelCount: 1, sampleRate: sampleRate))

        let output = render(stretcher, source: source, frames: 96_000) { frame in
            (Double(frame) * 1.25 / 48_000, 1.25)
        }

        let steady = output[9_600..<96_000]
        XCTAssertGreaterThan(magnitude(of: steady, frequency: 440), magnitude(of: steady, frequency: 550) * 4)
    }

    func testBeatsStayOnTheTimelineAcrossARateChange() throws {
        // A click every half second. Two seconds at 1x, then the same file continues at 2x.
        let source = try clickTrain(seconds: 10)
        let stretcher = try XCTUnwrap(LiveStretcher(channelCount: 1, sampleRate: sampleRate))

        let output = render(stretcher, source: source, frames: 192_000) { frame in
            frame < 96_000
                ? (Double(frame) / 48_000, 1)
                : (2 + Double(frame - 96_000) * 2 / 48_000, 2)
        }

        for expected in [24_000, 72_000, 108_000, 120_000, 168_000] {
            XCTAssertEqual(peak(in: output, near: expected), expected, accuracy: 240, "click at \(expected)")
        }
    }

    func testJumpingRestartsAtTheNewPosition() throws {
        let source = try clickTrain(seconds: 10)
        let stretcher = try XCTUnwrap(LiveStretcher(channelCount: 1, sampleRate: sampleRate))

        // Play from 0, then jump the source to 5.25 s: its next click (5.5 s) lands 0.25 s later.
        let output = render(stretcher, source: source, frames: 96_000) { frame in
            frame < 48_128
                ? (Double(frame) / 48_000, 1)
                : (5.25 + Double(frame - 48_128) / 48_000, 1)
        }

        XCTAssertEqual(peak(in: output, near: 48_128 + 12_000), 48_128 + 12_000, accuracy: 240)
    }
}
