import AVFoundation
import Foundation
import os

enum LTCGeneratorError: Error {
    case invalidDuration
}

/// Generates SMPTE LTC on demand for playback instead of materializing an entire
/// song-length PCM buffer into memory (which can exceed gigabytes for long songs).
final class ProceduralLTCBuffer: StemSampleSource, @unchecked Sendable {
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
    let audioFormat: AVAudioFormat

    private struct PhaseCheckpoint {
        let timecodeFrameOrdinal: Int
        let phasePositive: Bool
    }

    private let start: TimecodeValue
    private let frameRate: TimecodeFrameRate
    private let amplitude: Float
    private let samplesPerTimecodeFrame: Double
    private let samplesPerBit: Double

    /// Built on demand so song select stays cheap for long timecode tracks.
    private var checkpoints: [PhaseCheckpoint]
    private var streamPosition = 0
    private var streamLock = os_unfair_lock()

    init(
        duration: TimeInterval,
        start: TimecodeValue,
        frameRate: TimecodeFrameRate,
        sampleRate: Double = DecodedStemBuffer.engineSampleRate,
        amplitude: Float = LTCGenerator.amplitude
    ) throws {
        guard duration > 0, sampleRate > 0, duration.isFinite else {
            throw LTCGeneratorError.invalidDuration
        }

        let frames = (duration * sampleRate).rounded(.toNearestOrAwayFromZero)
        guard frames >= 1, frames <= Double(Int.max) else {
            throw LTCGeneratorError.invalidDuration
        }

        let samplesPerTimecodeFrame = sampleRate / frameRate.framesPerSecond
        guard samplesPerTimecodeFrame > 1 else {
            throw LTCGeneratorError.invalidDuration
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DecodedStemBufferError.unsupportedFormat
        }

        self.sampleRate = sampleRate
        self.channelCount = 1
        self.frameCount = Int(frames)
        self.audioFormat = format
        self.start = start
        self.frameRate = frameRate
        self.amplitude = amplitude
        self.samplesPerTimecodeFrame = samplesPerTimecodeFrame
        self.samplesPerBit = samplesPerTimecodeFrame / 80.0
        // Seed only the epoch checkpoint; extend lazily on first seek/render.
        self.checkpoints = [PhaseCheckpoint(timecodeFrameOrdinal: 0, phasePositive: true)]
    }

    func copy(
        channel: Int,
        startingFrame: Int,
        frameCount requestedFrames: Int,
        into destination: UnsafeMutablePointer<Float>,
        destinationOffset: Int,
        gain: Float
    ) -> Int {
        guard channel == 0 else { return 0 }
        guard startingFrame >= 0, startingFrame < frameCount else { return 0 }

        let available = min(requestedFrames, frameCount - startingFrame)
        guard available > 0 else { return 0 }

        os_unfair_lock_lock(&streamLock)
        seekLocked(to: startingFrame)
        for offset in 0..<available {
            let sample = renderNextSampleLocked()
            destination[destinationOffset + offset] = sample * gain
        }
        os_unfair_lock_unlock(&streamLock)

        return available
    }

    func interpolatedSample(channel: Int, frame: Double) -> Float {
        guard channel == 0, frameCount > 0, frame >= 0 else { return 0 }
        let index = frame >= Double(frameCount - 1) ? frameCount - 1 : Int(frame.rounded(.down))
        var sample: Float = 0
        os_unfair_lock_lock(&streamLock)
        seekLocked(to: index)
        sample = renderNextSampleLocked()
        os_unfair_lock_unlock(&streamLock)
        return sample
    }

    private func seekLocked(to sample: Int) {
        let clamped = max(0, min(sample, max(0, frameCount - 1)))
        guard clamped != streamPosition else { return }

        if clamped < streamPosition || clamped - streamPosition > Int(sampleRate * 2) {
            let targetFrame = Int((Double(clamped) / samplesPerTimecodeFrame).rounded(.down))
            streamPosition = Int((Double(targetFrame) * samplesPerTimecodeFrame).rounded(.down))
        }

        while streamPosition < clamped {
            _ = renderNextSampleLocked()
        }
    }

    private func renderNextSampleLocked() -> Float {
        guard streamPosition < frameCount else { return 0 }

        let timecodeFrameOrdinal = Int(
            (Double(streamPosition) / samplesPerTimecodeFrame).rounded(.down)
        )
        let frameStart = Int(
            (Double(timecodeFrameOrdinal) * samplesPerTimecodeFrame).rounded(.down)
        )
        let offsetInFrame = streamPosition - frameStart
        var phase = phaseAtStartOfTimecodeFrame(timecodeFrameOrdinal)
        let value = Self.sampleValue(
            offsetInFrame: offsetInFrame,
            timecodeFrameOrdinal: timecodeFrameOrdinal,
            start: start,
            frameRate: frameRate,
            samplesPerBit: samplesPerBit,
            amplitude: amplitude,
            phase: &phase
        )
        streamPosition += 1
        return value
    }

    private func phaseAtStartOfTimecodeFrame(_ ordinal: Int) -> Bool {
        guard ordinal > 0 else { return true }

        ensureCheckpoints(through: ordinal)

        let checkpoint = checkpoints.last(where: { $0.timecodeFrameOrdinal <= ordinal })
            ?? PhaseCheckpoint(timecodeFrameOrdinal: 0, phasePositive: true)

        var phase = checkpoint.phasePositive
        for index in checkpoint.timecodeFrameOrdinal..<ordinal {
            Self.advancePhase(
                throughTimecodeFrameOrdinal: index,
                start: start,
                frameRate: frameRate,
                phase: &phase
            )
        }
        return phase
    }

    /// Extends the checkpoint table far enough to cover `ordinal`. Caller must hold `streamLock`.
    private func ensureCheckpoints(through ordinal: Int) {
        let checkpointStride = 1_000
        guard let last = checkpoints.last else {
            checkpoints = [PhaseCheckpoint(timecodeFrameOrdinal: 0, phasePositive: true)]
            return
        }

        var phase = last.phasePositive
        var nextOrdinal = last.timecodeFrameOrdinal + checkpointStride
        while nextOrdinal <= ordinal {
            let sample = Int((Double(nextOrdinal) * samplesPerTimecodeFrame).rounded(.down))
            if sample >= frameCount { break }

            for index in checkpoints[checkpoints.count - 1].timecodeFrameOrdinal..<nextOrdinal {
                Self.advancePhase(
                    throughTimecodeFrameOrdinal: index,
                    start: start,
                    frameRate: frameRate,
                    phase: &phase
                )
            }
            checkpoints.append(PhaseCheckpoint(timecodeFrameOrdinal: nextOrdinal, phasePositive: phase))
            nextOrdinal += checkpointStride
        }
    }

    private static func advancePhase(
        throughTimecodeFrameOrdinal ordinal: Int,
        start: TimecodeValue,
        frameRate: TimecodeFrameRate,
        phase phaseInOut: inout Bool
    ) {
        let timecode = start.advanced(byFrames: ordinal, frameRate: frameRate)
        let bits = LTCFrameEncoder.bits(for: timecode, frameRate: frameRate)
        for bit in bits {
            phaseInOut.toggle()
            if bit {
                phaseInOut.toggle()
            }
        }
    }

    private static func sampleValue(
        offsetInFrame: Int,
        timecodeFrameOrdinal: Int,
        start: TimecodeValue,
        frameRate: TimecodeFrameRate,
        samplesPerBit: Double,
        amplitude: Float,
        phase: inout Bool
    ) -> Float {
        let timecode = start.advanced(byFrames: timecodeFrameOrdinal, frameRate: frameRate)
        let bits = LTCFrameEncoder.bits(for: timecode, frameRate: frameRate)

        for bitIndex in 0..<80 {
            phase.toggle()
            let bitStart = Int((Double(bitIndex) * samplesPerBit).rounded(.down))
            let bitMid = Int(((Double(bitIndex) + 0.5) * samplesPerBit).rounded(.down))
            let bitEnd = Int(((Double(bitIndex) + 1.0) * samplesPerBit).rounded(.down))

            if offsetInFrame >= bitStart && offsetInFrame < (bits[bitIndex] ? bitMid : bitEnd) {
                return phase ? amplitude : -amplitude
            }

            if bits[bitIndex] {
                if offsetInFrame >= bitMid && offsetInFrame < bitEnd {
                    phase.toggle()
                    return phase ? amplitude : -amplitude
                }
                phase.toggle()
            }
        }

        return 0
    }
}

enum LTCGenerator {
    /// Approx −9 dBFS square amplitude for reliable desk lock.
    static let amplitude: Float = 0.35

    static func generate(
        duration: TimeInterval,
        start: TimecodeValue,
        frameRate: TimecodeFrameRate,
        sampleRate: Double = DecodedStemBuffer.engineSampleRate,
        amplitude: Float = amplitude
    ) throws -> DecodedStemBuffer {
        guard duration > 0, sampleRate > 0 else {
            throw LTCGeneratorError.invalidDuration
        }

        let frameCount = max(1, Int((duration * sampleRate).rounded(.toNearestOrAwayFromZero)))
        let output = try DecodedStemBuffer.silent(frameCount: frameCount, sampleRate: sampleRate)
        let samplesPerTimecodeFrame = sampleRate / frameRate.framesPerSecond
        guard samplesPerTimecodeFrame > 1 else {
            throw LTCGeneratorError.invalidDuration
        }

        let samplesPerBit = samplesPerTimecodeFrame / 80.0
        var phasePositive = true
        var frameOrdinal = 0
        var timecode = start

        output.withMutableSamples(channel: 0) { samples, count in
            while true {
                let frameStart = Int((Double(frameOrdinal) * samplesPerTimecodeFrame).rounded(.down))
                if frameStart >= count {
                    break
                }

                let bits = LTCFrameEncoder.bits(for: timecode, frameRate: frameRate)
                for bitIndex in 0..<80 {
                    // Bi-phase mark: transition at every bit boundary.
                    phasePositive.toggle()
                    let bitStart = frameStart + Int((Double(bitIndex) * samplesPerBit).rounded(.down))
                    let bitMid = frameStart + Int(((Double(bitIndex) + 0.5) * samplesPerBit).rounded(.down))
                    let bitEnd = frameStart + Int(((Double(bitIndex) + 1.0) * samplesPerBit).rounded(.down))

                    fill(
                        samples,
                        count: count,
                        from: bitStart,
                        to: bits[bitIndex] ? bitMid : bitEnd,
                        value: phasePositive ? amplitude : -amplitude
                    )

                    if bits[bitIndex] {
                        phasePositive.toggle()
                        fill(
                            samples,
                            count: count,
                            from: bitMid,
                            to: bitEnd,
                            value: phasePositive ? amplitude : -amplitude
                        )
                    }
                }

                frameOrdinal += 1
                timecode = start.advanced(byFrames: frameOrdinal, frameRate: frameRate)
            }
        }

        return output
    }

    private static func fill(
        _ samples: UnsafeMutablePointer<Float>,
        count: Int,
        from start: Int,
        to end: Int,
        value: Float
    ) {
        let clampedStart = max(0, start)
        let clampedEnd = min(count, end)
        guard clampedStart < clampedEnd else { return }
        for frame in clampedStart..<clampedEnd {
            samples[frame] = value
        }
    }
}
