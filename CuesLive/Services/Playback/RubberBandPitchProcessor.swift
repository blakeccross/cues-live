import Foundation

enum RubberBandPitchProcessor {
    static func pitchShift(buffer: DecodedStemBuffer, semitones: Int) throws -> DecodedStemBuffer {
        guard semitones != 0 else { return buffer }

        let channelPointers = (0..<buffer.channelCount).map { buffer.channelPointer($0) }
        let optionalPointers = channelPointers.map { Optional($0) }

        let result = optionalPointers.withUnsafeBufferPointer { optionalBuffer in
            guard let optionalBase = optionalBuffer.baseAddress else {
                return PitchShiftResult(channels: nil, channelCount: 0, frameCount: 0)
            }
            return pitch_shift_offline(
                optionalBase,
                Int32(buffer.channelCount),
                Int32(buffer.frameCount),
                buffer.sampleRate,
                Int32(semitones)
            )
        }
        defer { pitch_shift_free_result(result) }

        guard
            result.channels != nil,
            result.channelCount > 0,
            result.frameCount > 0
        else {
            throw DecodedStemBufferError.pitchShiftFailed
        }

        return try DecodedStemBuffer.fromPitchShiftResult(
            result,
            sampleRate: buffer.sampleRate,
            audioFormat: buffer.audioFormat
        )
    }
}
