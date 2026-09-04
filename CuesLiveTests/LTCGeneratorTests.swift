import XCTest
@testable import CuesLive

final class LTCGeneratorTests: XCTestCase {
    func testGeneratedBufferHasExpectedLength() throws {
        let duration: TimeInterval = 1
        let buffer = try LTCGenerator.generate(
            duration: duration,
            start: .atHour(1),
            frameRate: .fps30
        )

        let expectedFrames = Int((duration * DecodedStemBuffer.engineSampleRate).rounded())
        XCTAssertEqual(buffer.frameCount, expectedFrames)
        XCTAssertEqual(buffer.channelCount, 1)
    }

    func testGeneratedBufferIsNotSilent() throws {
        let buffer = try LTCGenerator.generate(
            duration: 0.5,
            start: .atHour(1),
            frameRate: .fps30
        )

        var peak: Float = 0
        buffer.withMutableSamples(channel: 0) { samples, count in
            for index in 0..<count {
                peak = max(peak, abs(samples[index]))
            }
        }
        XCTAssertGreaterThan(peak, 0.2)
        XCTAssertLessThanOrEqual(peak, LTCGenerator.amplitude + 0.001)
    }

    func testZeroCrossingRateIsInLTCBandAt30FPS() throws {
        let buffer = try LTCGenerator.generate(
            duration: 1,
            start: .atHour(1),
            frameRate: .fps30
        )

        var crossings = 0
        buffer.withMutableSamples(channel: 0) { samples, count in
            guard count > 1 else { return }
            for index in 1..<count {
                if samples[index - 1] == 0 || samples[index] == 0 { continue }
                if samples[index - 1].sign != samples[index].sign {
                    crossings += 1
                }
            }
        }

        // At 30 fps: zeros ≈ 1.2 kHz transitions, ones ≈ 2.4 kHz.
        // Mixed frames (with sync ones) typically land between those extremes,
        // and can approach ~4.8 kHz if a stretch is dense with ones.
        let rate = Double(crossings)
        XCTAssertGreaterThan(rate, 800)
        XCTAssertLessThan(rate, 5_000)
    }

    func testInvalidDurationThrows() {
        XCTAssertThrowsError(
            try LTCGenerator.generate(
                duration: 0,
                start: .atHour(1),
                frameRate: .fps30
            )
        )
    }

    func testProceduralBufferMatchesMaterializedGenerator() throws {
        let duration: TimeInterval = 1
        let materialized = try LTCGenerator.generate(
            duration: duration,
            start: .atHour(1),
            frameRate: .fps30
        )
        let procedural = try ProceduralLTCBuffer(
            duration: duration,
            start: .atHour(1),
            frameRate: .fps30
        )

        XCTAssertEqual(procedural.frameCount, materialized.frameCount)

        var destination = [Float](repeating: 0, count: procedural.frameCount)
        destination.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = procedural.copy(
                channel: 0,
                startingFrame: 0,
                frameCount: procedural.frameCount,
                into: base,
                destinationOffset: 0,
                gain: 1
            )
        }

        materialized.withMutableSamples(channel: 0) { samples, count in
            for index in 0..<count {
                XCTAssertEqual(destination[index], samples[index], accuracy: 0.0001, "sample \(index)")
            }
        }
    }

    func testLongProceduralBufferInitIsCheap() throws {
        let start = CFAbsoluteTimeGetCurrent()
        let buffer = try ProceduralLTCBuffer(
            duration: 79 * 60,
            start: .atHour(1),
            frameRate: .fps30
        )
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000

        XCTAssertGreaterThan(buffer.frameCount, 1_000_000)
        XCTAssertLessThan(elapsedMS, 250, "lazy LTC checkpoints should not scan the full song at init")

        // Touch a late sample so checkpoints extend on demand.
        let lateStart = Int(70 * 60 * buffer.sampleRate)
        var sample: Float = 0
        _ = withUnsafeMutablePointer(to: &sample) { pointer in
            buffer.copy(
                channel: 0,
                startingFrame: lateStart,
                frameCount: 1,
                into: pointer,
                destinationOffset: 0,
                gain: 1
            )
        }
        XCTAssertNotEqual(sample, 0)
    }
}
