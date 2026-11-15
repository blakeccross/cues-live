import AVFoundation
import Observation

/// Loops a spoken output identification on one hardware destination until stopped,
/// or tests many outputs together through `startAllOutputs` in `+AllOutputs`.
@Observable
@MainActor
final class OutputChannelTestPlayer {
    static let shared = OutputChannelTestPlayer()

    private(set) var activeRouteID: UUID?
    /// The Test All Outputs run in progress, if any.
    var activeAllOutputsPlan: OutputTestPlan?
    /// The output sounding right now during an in-series run.
    var currentSeriesDestination: OutputDestination?
    /// Outputs whose signal is ready and playing. All-at-once announce runs add outputs
    /// to the mix as their phrases finish rendering.
    var preparedOutputCount = 0
    var allOutputsTask: Task<Void, Never>?

    private let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    var generation = 0
    private var didSuspendSharedEngine = false
    private var isGraphReady = false
    private var isStopping = false
    private var wiredChannelCount = 0
    private var wiredDeviceUID: String?
    private var speechSession: OutputTestSpeechSession?
    /// Rendered phrases by text. Speech takes about a third of a second per phrase, so a
    /// 34-output interface would otherwise wait seconds on every run.
    @ObservationIgnored private var renderedPhrases: [String: AVAudioPCMBuffer] = [:]

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
        endAllOutputsTest()
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
        guard let playback = OutputTestSignalBuilder.multiChannelBuffer(
            [OutputTestSignalBuilder.Layer(mono: mono, destination: destination)],
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
        player.scheduleBuffer(
            playback,
            at: nil,
            options: [],
            completionCallbackType: .dataConsumed,
            completionHandler: nil
        )
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
        let token = beginTest()
        activeRouteID = routeID
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

    /// Silences any running test and claims the hardware for a new one.
    /// Returns the new run's token; work that finds `generation` changed has been superseded.
    func beginTest() -> Int {
        endAllOutputsTest()
        generation += 1
        activeRouteID = nil
        if player.engine != nil {
            player.stop()
        }
        suspendSharedEngineIfNeeded()
        return generation
    }

    func stop() {
        endAllOutputsTest()
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
        guard let playback = OutputTestSignalBuilder.multiChannelBuffer(
            [OutputTestSignalBuilder.Layer(mono: mono, destination: destination)],
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
    func scheduleLoop(_ buffer: AVAudioPCMBuffer) {
        player.scheduleBuffer(buffer, at: nil, options: .loops)
    }

    func ensureGraph(deviceUID: String?, channelCount: Int) throws {
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

    func isPhraseCached(_ phrase: String) -> Bool {
        renderedPhrases[phrase] != nil
    }

    static func renderLoopingMonoBuffer(phrase: String) async -> AVAudioPCMBuffer? {
        if let cached = OutputChannelTestPlayer.shared.renderedPhrases[phrase] {
            return cached
        }
        let session = OutputTestSpeechSession()
        OutputChannelTestPlayer.shared.speechSession = session
        let spoken = await OutputTestSpeech.render(phrase, synthesizer: session.synthesizer)
        // Stop clears the session and cuts speech short; a cut phrase must not be cached.
        let finished = OutputChannelTestPlayer.shared.speechSession === session
        if finished {
            OutputChannelTestPlayer.shared.speechSession = nil
        }
        guard let spoken else { return nil }
        guard let stem = try? DecodedStemBuffer.monoStem(from: spoken),
              let buffer = OutputTestSignalBuilder.monoBuffer(stem: stem, trailingSilence: trailingSilenceSeconds) else {
            return nil
        }
        if finished {
            OutputChannelTestPlayer.shared.renderedPhrases[phrase] = buffer
        }
        return buffer
    }
}

private enum OutputChannelTestError: Error {
    case unsupportedFormat
}

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
