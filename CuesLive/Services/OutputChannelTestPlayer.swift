import AVFoundation
import Observation

/// Loops a spoken output identification on one hardware destination until stopped.
@Observable
@MainActor
final class OutputChannelTestPlayer {
    static let shared = OutputChannelTestPlayer()

    private(set) var activeRouteID: UUID?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var generation = 0
    private var didSuspendSharedEngine = false
    private var isGraphReady = false
    private var isStopping = false
    private var wiredChannelCount = 0
    private var wiredDeviceUID: String?
    private var speechSession: OutputTestSpeechSession?

    private static let trailingSilenceSeconds: Double = 0.55

    private init() {}

    func isTesting(_ routeID: UUID) -> Bool {
        activeRouteID == routeID
    }

    var isAudible: Bool {
        engine.isRunning && player.isPlaying
    }

    private(set) var lastGraphDescription = ""

    /// Plays one phrase and returns the peak level heard on each mixer output channel.
    func measureChannelPeaks(
        destination: OutputDestination,
        channelCount: Int,
        deviceUID: String? = nil
    ) async -> [Float] {
        generation += 1
        let token = generation
        guard let mono = await Self.renderLoopingMonoBuffer(phrase: destination.testPhrase) else {
            return []
        }
        guard token == generation else { return [] }
        let channels = max(channelCount, 2)
        do {
            try ensureGraph(deviceUID: deviceUID, channelCount: channels)
        } catch {
            return []
        }
        let outputFormat = player.outputFormat(forBus: 0)
        guard let playback = Self.multiChannelBuffer(
            from: mono,
            destination: destination,
            format: outputFormat
        ) else {
            return []
        }

        let tapNode = engine.mainMixerNode
        let tapFormat = tapNode.outputFormat(forBus: 0)
        let meter = OutputTestPeakMeter(channelCount: Int(tapFormat.channelCount))
        tapNode.removeTap(onBus: 0)
        tapNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            meter.observe(buffer)
        }
        player.scheduleBuffer(playback, at: nil, options: []) {}
        player.play()
        try? await Task.sleep(nanoseconds: 700_000_000)
        tapNode.removeTap(onBus: 0)
        stop()
        return meter.peaks
    }

    func start(
        routeID: UUID,
        destination: OutputDestination,
        deviceUID: String?,
        channelCount: Int
    ) {
        generation += 1
        let token = generation
        activeRouteID = routeID
        if player.engine != nil {
            player.stop()
        }
        suspendSharedEngineIfNeeded()
        let phrase = destination.testPhrase

        Task { @MainActor in
            guard let mono = await Self.renderLoopingMonoBuffer(phrase: phrase) else {
                guard token == self.generation else { return }
                self.stop()
                return
            }
            guard token == self.generation else { return }
            self.play(
                mono,
                destination: destination,
                deviceUID: deviceUID,
                channelCount: channelCount
            )
        }
    }

    func stop() {
        generation += 1
        activeRouteID = nil
        if isStopping { return }
        isStopping = true
        let session = speechSession
        speechSession = nil
        session?.stop()
        if player.engine != nil {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        resumeSharedEngineIfNeeded()
        isStopping = false
    }

    // MARK: - Playback

    private func play(
        _ mono: AVAudioPCMBuffer,
        destination: OutputDestination,
        deviceUID: String?,
        channelCount: Int
    ) {
        let channels = max(channelCount, 2)
        do {
            try ensureGraph(deviceUID: deviceUID, channelCount: channels)
        } catch {
            stop()
            return
        }

        let outputFormat = player.outputFormat(forBus: 0)
        guard let playback = Self.multiChannelBuffer(
            from: mono,
            destination: destination,
            format: outputFormat
        ) else {
            stop()
            return
        }

        if player.isPlaying {
            player.stop()
        }
        scheduleLoop(playback)
        player.play()
    }

    /// One schedule with `.loops`. A completion that hops to the main actor from the
    /// audio thread aborts that task when Stop calls `player.stop()`.
    private func scheduleLoop(_ buffer: AVAudioPCMBuffer) {
        player.scheduleBuffer(buffer, at: nil, options: .loops)
    }

    private func ensureGraph(deviceUID: String?, channelCount: Int) throws {
        if isGraphReady, wiredChannelCount == channelCount, wiredDeviceUID == deviceUID {
            if !engine.isRunning {
                suspendSharedEngineIfNeeded()
                try engine.start()
            }
            return
        }

        tearDownEngine()
        suspendSharedEngineIfNeeded()

        if player.engine == nil {
            engine.attach(player)
        }

        guard let format = AudioOutputDeviceService.multiChannelFormat(
            sampleRate: DecodedStemBuffer.engineSampleRate,
            channelCount: channelCount
        ) else {
            throw OutputChannelTestError.unsupportedFormat
        }

        // Bind before connecting. Preparing an unconnected engine raises, and
        // preparing after the connection drops it and plays silence.
        if let deviceUID {
            AudioOutputDeviceService.bindOutputDevice(uid: deviceUID, to: engine)
        }

        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.auAudioUnit.channelMap = nil
        player.volume = 1
        engine.mainMixerNode.outputVolume = 1

        try engine.start()
        isGraphReady = true
        wiredChannelCount = channelCount
        wiredDeviceUID = deviceUID
        lastGraphDescription = """
        connected \(format) running=\(engine.isRunning)
        player \(player.outputFormat(forBus: 0))
        mixer \(engine.mainMixerNode.outputFormat(forBus: 0))
        outputIn \(engine.outputNode.inputFormat(forBus: 0))
        outputOut \(engine.outputNode.outputFormat(forBus: 0))
        """
    }

    private func tearDownEngine() {
        if player.engine != nil {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        if player.engine != nil {
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        isGraphReady = false
        wiredChannelCount = 0
        wiredDeviceUID = nil
    }

    private func suspendSharedEngineIfNeeded() {
        guard !didSuspendSharedEngine else { return }
        if AudioEngineManager.shared.isPlaying {
            AudioEngineManager.shared.pause()
        }
        AudioEngineManager.shared.suspendHardware()
        didSuspendSharedEngine = true
    }

    private func resumeSharedEngineIfNeeded() {
        guard didSuspendSharedEngine else { return }
        didSuspendSharedEngine = false
        AudioEngineManager.shared.resumeHardware()
    }

    // MARK: - Speech

    private static func renderLoopingMonoBuffer(phrase: String) async -> AVAudioPCMBuffer? {
        let session = OutputTestSpeechSession()
        OutputChannelTestPlayer.shared.speechSession = session
        let spoken = await OutputTestSpeech.render(phrase, synthesizer: session.synthesizer)
        if OutputChannelTestPlayer.shared.speechSession === session {
            OutputChannelTestPlayer.shared.speechSession = nil
        }
        guard let spoken else { return nil }
        guard let stem = try? DecodedStemBuffer.monoStem(from: spoken) else { return nil }
        return monoBuffer(stem: stem, trailingSilence: trailingSilenceSeconds)
    }

    private static func monoBuffer(stem: DecodedStemBuffer, trailingSilence seconds: Double) -> AVAudioPCMBuffer? {
        let silenceFrames = max(0, Int((stem.sampleRate * seconds).rounded()))
        let total = stem.frameCount + silenceFrames
        guard total > 0 else { return nil }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: stem.sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(total)
        ), let channel = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(total)
        if silenceFrames > 0 {
            let tail = channel.advanced(by: stem.frameCount)
            for frame in 0..<silenceFrames {
                tail[frame] = 0
            }
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

    /// Writes the phrase onto the destination's hardware channels in the player's format.
    /// Output 2 is buffer channel 1. The buffer must match `player.outputFormat` or scheduling throws.
    private static func multiChannelBuffer(
        from mono: AVAudioPCMBuffer,
        destination: OutputDestination,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard format.channelCount > 0,
              format.sampleRate > 0,
              format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              let sourceBuffer = matchedRateBuffer(mono, sampleRate: format.sampleRate),
              let source = sourceBuffer.floatChannelData?[0] else {
            return nil
        }
        let frames = Int(sourceBuffer.frameLength)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frames)
        let outputChannels = Int(format.channelCount)
        for channel in 0..<outputChannels {
            let samples = channels[channel]
            for frame in 0..<frames {
                samples[frame] = 0
            }
        }
        for index in destination.testChannelIndexes(outputChannelCount: outputChannels) where index < outputChannels {
            channels[index].update(from: source, count: frames)
        }
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

private enum OutputChannelTestError: Error {
    case unsupportedFormat
}

/// Holds the in-flight synthesizer so Stop can cancel it without touching the callback.
private final class OutputTestPeakMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Float]

    init(channelCount: Int) {
        values = Array(repeating: 0, count: channelCount)
    }

    func observe(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        lock.lock()
        let count = min(values.count, Int(buffer.format.channelCount))
        for channel in 0..<count {
            let samples = data[channel]
            for frame in 0..<frameCount {
                values[channel] = max(values[channel], abs(samples[frame]))
            }
        }
        lock.unlock()
    }

    var peaks: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class OutputTestSpeechSession: @unchecked Sendable {
    let synthesizer = AVSpeechSynthesizer()

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

/// Speech callbacks arrive off the main thread. This type stays nonisolated so those
/// callbacks are not treated as main-actor work, which aborts the waiting task.
private enum OutputTestSpeech {
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
