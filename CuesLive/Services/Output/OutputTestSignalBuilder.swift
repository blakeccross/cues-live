import AVFoundation

/// Builds the PCM buffers the output test plays: spoken phrases, pink noise, and the
/// multichannel buffers that place them on hardware outputs.
enum OutputTestSignalBuilder {
    /// One mono signal and the destination whose channels carry it.
    struct Layer {
        let mono: AVAudioPCMBuffer
        let destination: OutputDestination
    }

    /// Pink noise peaks near -6 dBFS with this gain, comfortable for a speaker check.
    private static let pinkNoiseGain: Float = 0.08

    /// Copies a decoded phrase into a mono buffer and pads it with silence so loops breathe.
    static func monoBuffer(stem: DecodedStemBuffer, trailingSilence seconds: Double) -> AVAudioPCMBuffer? {
        let silenceFrames = max(0, Int((stem.sampleRate * seconds).rounded()))
        let total = stem.frameCount + silenceFrames
        guard let buffer = makeMonoBuffer(sampleRate: stem.sampleRate, frameCount: total),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        _ = stem.copy(
            channel: 0,
            startingFrame: 0,
            frameCount: stem.frameCount,
            into: channel,
            destinationOffset: 0,
            gain: 1
        )
        return buffer
    }

    /// Mono pink noise with linear fades at both ends, followed by silence.
    static func pinkNoise(
        sampleRate: Double,
        duration: Double,
        fade: Double = 0,
        trailingSilence: Double = 0
    ) -> AVAudioPCMBuffer? {
        let noiseFrames = max(0, Int((sampleRate * duration).rounded()))
        let silenceFrames = max(0, Int((sampleRate * trailingSilence).rounded()))
        guard noiseFrames > 0,
              let buffer = makeMonoBuffer(sampleRate: sampleRate, frameCount: noiseFrames + silenceFrames),
              let samples = buffer.floatChannelData?[0] else {
            return nil
        }

        // Paul Kellet's economy pink filter over uniform white noise.
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var generator = SystemRandomNumberGenerator()
        let fadeFrames = min(noiseFrames / 2, max(0, Int((sampleRate * fade).rounded())))
        for frame in 0..<noiseFrames {
            let white = Float.random(in: -1...1, using: &generator)
            b0 = 0.99765 * b0 + white * 0.0990
            b1 = 0.96300 * b1 + white * 0.2965
            b2 = 0.57000 * b2 + white * 1.0526
            let pink = (b0 + b1 + b2 + white * 0.1848) * pinkNoiseGain
            samples[frame] = pink * envelope(frame: frame, total: noiseFrames, fadeFrames: fadeFrames)
        }
        return buffer
    }

    /// Mixes every layer onto its destination's hardware channels, all starting at frame zero,
    /// in the player's format. Output 2 is buffer channel 1. The buffer must match
    /// `player.outputFormat` or scheduling throws.
    static func multiChannelBuffer(_ layers: [Layer], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard format.channelCount > 0,
              format.sampleRate > 0,
              format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else {
            return nil
        }
        let sources = layers.compactMap { layer -> (AVAudioPCMBuffer, OutputDestination)? in
            guard let matched = matchedRateBuffer(layer.mono, sampleRate: format.sampleRate) else { return nil }
            return (matched, layer.destination)
        }
        let frames = sources.map { Int($0.0.frameLength) }.max() ?? 0
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frames)
        let outputChannels = Int(format.channelCount)
        for channel in 0..<outputChannels {
            channels[channel].update(repeating: 0, count: frames)
        }
        for (source, destination) in sources {
            guard let samples = source.floatChannelData?[0] else { continue }
            let count = Int(source.frameLength)
            for index in destination.testChannelIndexes(outputChannelCount: outputChannels) where index < outputChannels {
                let target = channels[index]
                for frame in 0..<count {
                    target[frame] = min(max(target[frame] + samples[frame], -1), 1)
                }
            }
        }
        return buffer
    }

    private static func envelope(frame: Int, total: Int, fadeFrames: Int) -> Float {
        guard fadeFrames > 0 else { return 1 }
        let fromEdge = min(frame, total - 1 - frame)
        return fromEdge < fadeFrames ? Float(fromEdge) / Float(fadeFrames) : 1
    }

    /// A zero-filled mono float buffer of `frameCount` frames.
    private static func makeMonoBuffer(sampleRate: Double, frameCount: Int) -> AVAudioPCMBuffer? {
        guard frameCount > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        channel.update(repeating: 0, count: frameCount)
        return buffer
    }

    private static func matchedRateBuffer(_ mono: AVAudioPCMBuffer, sampleRate: Double) -> AVAudioPCMBuffer? {
        if mono.format.sampleRate == sampleRate { return mono }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: mono.format, to: format) else {
            return nil
        }
        let ratio = sampleRate / mono.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(mono.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        let input: AVAudioConverterInputBlock = { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return mono
        }
        converter.convert(to: output, error: &error, withInputFrom: input)
        if error != nil || output.frameLength == 0 { return nil }
        return output
    }
}
