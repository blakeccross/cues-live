import AVFoundation

/// Holds the in-flight synthesizer so Stop can cancel it without touching the callback.
final class OutputTestSpeechSession: @unchecked Sendable {
    let synthesizer = AVSpeechSynthesizer()

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

/// Speech callbacks arrive off the main thread. This type stays nonisolated so those
/// callbacks are not treated as main-actor work, which aborts the waiting task.
enum OutputTestSpeech {
    static func render(_ text: String, synthesizer: AVSpeechSynthesizer) async -> AVAudioPCMBuffer? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        return await withCheckedContinuation { continuation in
            let accumulator = SpeechChunkAccumulator()
            let gate = ResumeGate(continuation: continuation)
            let timeout = Task.detached {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                synthesizer.stopSpeaking(at: .immediate)
                gate.resume(nil)
            }

            synthesizer.write(utterance) { [synthesizer] buffer in
                _ = synthesizer
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    timeout.cancel()
                    gate.resume(makePCMBuffer(samples: accumulator.samples, sampleRate: accumulator.sampleRate))
                    return
                }
                append(pcm, to: accumulator)
            }
        }
    }

    private static func append(_ buffer: AVAudioPCMBuffer, to accumulator: SpeechChunkAccumulator) {
        guard buffer.frameLength > 0 else { return }
        guard let mono = monoFloatBuffer(from: buffer),
              let data = mono.floatChannelData?[0] else { return }

        let frames = Int(mono.frameLength)
        guard frames > 0 else { return }
        if accumulator.sampleRate == 0 {
            accumulator.sampleRate = mono.format.sampleRate
        }

        let samples: [Float]
        if mono.format.sampleRate != accumulator.sampleRate {
            guard let matched = convert(mono, toSampleRate: accumulator.sampleRate),
                  let matchedData = matched.floatChannelData?[0] else { return }
            let matchedFrames = Int(matched.frameLength)
            guard matchedFrames > 0 else { return }
            samples = Array(UnsafeBufferPointer(start: matchedData, count: matchedFrames))
        } else {
            samples = Array(UnsafeBufferPointer(start: data, count: frames))
        }
        accumulator.append(samples)
    }

    private static func monoFloatBuffer(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format.commonFormat == .pcmFormatFloat32,
           buffer.format.channelCount == 1,
           !buffer.format.isInterleaved,
           buffer.floatChannelData != nil {
            return buffer
        }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        return convert(buffer, to: monoFormat)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, toSampleRate sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        return convert(buffer, to: format)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var error: NSError?
        let input = ConverterInput(buffer)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if input.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            input.consumed = true
            outStatus.pointee = .haveData
            return input.buffer
        }
        converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        if error != nil || output.frameLength == 0 {
            return nil
        }
        return output
    }

    private static func makePCMBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        return buffer
    }
}

private final class ConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var consumed = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

private final class SpeechChunkAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Float] = []
    var sampleRate: Double = 0

    var samples: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: [Float]) {
        lock.lock()
        storage.append(contentsOf: chunk)
        lock.unlock()
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AVAudioPCMBuffer?, Never>?

    init(continuation: CheckedContinuation<AVAudioPCMBuffer?, Never>) {
        self.continuation = continuation
    }

    func resume(_ buffer: AVAudioPCMBuffer?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: buffer)
    }
}
