import AVFoundation

/// Test All Outputs: plays one plan across many outputs, together or one after another,
/// until `stop()`.
///
/// Both orders schedule one cycle at a time a little ahead of the playhead. In series a cycle
/// is one output; all at once, a cycle mixes every output whose signal is ready, so sound starts
/// after the first phrase renders and the rest join as they finish.
extension OutputChannelTestPlayer {
    /// Audio kept scheduled ahead of the playhead.
    private static let lookaheadSeconds: Double = 2
    private static let pollNanoseconds: UInt64 = 100_000_000
    private static let seriesNoiseSeconds: Double = 2
    private static let seriesNoiseGapSeconds: Double = 0.5
    private static let seriesNoiseFadeSeconds: Double = 0.02
    private static let simultaneousNoiseSeconds: Double = 4

    var isTestingAllOutputs: Bool {
        activeAllOutputsPlan != nil
    }

    /// Starts testing `destinations` the way `plan` describes. In series, each output plays
    /// its signal once in order and the run repeats from the first output.
    func startAllOutputs(
        _ plan: OutputTestPlan,
        destinations: [OutputDestination],
        deviceUID: String?,
        channelCount: Int
    ) {
        let token = beginTest()
        guard !destinations.isEmpty else {
            stop()
            return
        }
        activeAllOutputsPlan = plan
        let channels = max(channelCount, 2)
        allOutputsTask = Task { @MainActor in
            await self.runAllOutputs(plan, on: destinations, deviceUID: deviceUID, channelCount: channels, token: token)
        }
    }

    /// Clears Test All Outputs state. Called by every path that starts or stops a test.
    func endAllOutputsTest() {
        allOutputsTask?.cancel()
        allOutputsTask = nil
        activeAllOutputsPlan = nil
        currentSeriesDestination = nil
        preparedOutputCount = 0
    }

    private func isCurrent(_ token: Int) -> Bool {
        token == generation && !Task.isCancelled
    }

    private func runAllOutputs(
        _ plan: OutputTestPlan,
        on destinations: [OutputDestination],
        deviceUID: String?,
        channelCount: Int,
        token: Int
    ) async {
        do {
            try ensureGraph(deviceUID: deviceUID, channelCount: channelCount)
        } catch {
            stop()
            return
        }
        var run = OutputTestRun(plan: plan, destinations: destinations, format: player.outputFormat(forBus: 0))
        let lookahead = AVAudioFramePosition(run.format.sampleRate * Self.lookaheadSeconds)

        while isCurrent(token) {
            let playhead = playheadFrame() ?? 0
            while run.scheduledEnd - playhead < lookahead {
                let cycle = await nextCycle(of: &run)
                guard isCurrent(token) else { return }
                guard let cycle else {
                    stop()
                    return
                }
                schedule(cycle, in: &run)
            }
            showSoundingOutput(in: &run, at: playhead)

            if plan.timing == .simultaneous, let pending = run.nextUnprepared {
                await prepare(pending, in: &run)
            } else {
                try? await Task.sleep(nanoseconds: Self.pollNanoseconds)
            }
        }
    }

    /// The next buffer to play and, in series, the output it sounds on.
    /// Nil once no output can produce a signal.
    private func nextCycle(of run: inout OutputTestRun) async -> OutputTestCycle? {
        switch run.plan.timing {
        case .series:
            for _ in run.destinations.indices {
                let destination = run.destinations[run.cursor % run.destinations.count]
                run.cursor += 1
                if run.failed.contains(destination) { continue }
                if run.signals[destination] == nil {
                    await prepare(destination, in: &run)
                }
                guard let mono = run.signals[destination],
                      let buffer = OutputTestSignalBuilder.multiChannelBuffer(
                          [OutputTestSignalBuilder.Layer(mono: mono, destination: destination)],
                          format: run.format
                      ) else { continue }
                return OutputTestCycle(buffer: buffer, output: destination)
            }
            return nil
        case .simultaneous:
            let signal = run.plan.signal
            while let pending = run.outputToPrepareBeforeCycle(isInstant: { self.isInstant(signal, for: $0) }) {
                await prepare(pending, in: &run)
            }
            let layers = run.destinations.compactMap { destination in
                run.signals[destination].map { OutputTestSignalBuilder.Layer(mono: $0, destination: destination) }
            }
            return OutputTestSignalBuilder.multiChannelBuffer(layers, format: run.format)
                .map { OutputTestCycle(buffer: $0, output: nil) }
        }
    }

    private func schedule(_ cycle: OutputTestCycle, in run: inout OutputTestRun) {
        let start = AVAudioTime(sampleTime: run.scheduledEnd, atRate: run.format.sampleRate)
        player.scheduleBuffer(
            cycle.buffer,
            at: start,
            options: [],
            completionCallbackType: .dataConsumed,
            completionHandler: nil
        )
        if let output = cycle.output {
            run.starts.append((run.scheduledEnd, output))
        }
        run.scheduledEnd += AVAudioFramePosition(cycle.buffer.frameLength)
        if !player.isPlaying {
            player.play()
        }
    }

    private func showSoundingOutput(in run: inout OutputTestRun, at playhead: AVAudioFramePosition) {
        guard let sounding = run.starts.lastIndex(where: { $0.frame <= playhead }) else { return }
        let output = run.starts[sounding].output
        if currentSeriesDestination != output {
            currentSeriesDestination = output
        }
        run.starts.removeFirst(sounding)
    }

    /// Whether an output's signal is ready without waiting on speech.
    private func isInstant(_ signal: OutputTestPlan.Signal, for destination: OutputDestination) -> Bool {
        signal == .noise || isPhraseCached(destination.testPhrase)
    }

    /// Renders one output's signal into the run, or marks it failed so it is not retried.
    private func prepare(_ destination: OutputDestination, in run: inout OutputTestRun) async {
        let rendered: AVAudioPCMBuffer?
        switch (run.plan.signal, run.plan.timing) {
        case (.noise, .series):
            rendered = OutputTestSignalBuilder.pinkNoise(
                sampleRate: run.format.sampleRate,
                duration: Self.seriesNoiseSeconds,
                fade: Self.seriesNoiseFadeSeconds,
                trailingSilence: Self.seriesNoiseGapSeconds
            )
        case (.noise, .simultaneous):
            rendered = OutputTestSignalBuilder.pinkNoise(
                sampleRate: run.format.sampleRate,
                duration: Self.simultaneousNoiseSeconds
            )
        case (.announce, _):
            rendered = await Self.renderLoopingMonoBuffer(phrase: destination.testPhrase)
        }
        if let rendered {
            run.signals[destination] = rendered
        } else {
            run.failed.insert(destination)
        }
        if preparedOutputCount != run.signals.count {
            preparedOutputCount = run.signals.count
        }
    }

    /// Frames the player has rendered since `play()`, or nil before it starts rendering.
    private func playheadFrame() -> AVAudioFramePosition? {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return playerTime.sampleTime
    }
}

/// One scheduled buffer and, in series, the output it sounds on.
private struct OutputTestCycle {
    let buffer: AVAudioPCMBuffer
    let output: OutputDestination?
}
