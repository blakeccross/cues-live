import AVFoundation
import Foundation

/// Connecting the mixer to the output device, at the device's width and the selected rate.
extension AudioEngineManager {
    func wireTrackOutputs(routing: OutputRoutingSnapshot) throws {
        stopEngineForGraphChanges()
        let boundRequestedDevice = adoptOutputDevice(routing.deviceUID)
        // A stale/missing device UID must not force a multi-channel layout onto whatever
        // output the engine actually opened — that leaves the graph silent.
        let channelCount = (routing.deviceUID != nil && !boundRequestedDevice)
            ? 2
            : outputChannelCount(for: routing)
        connectMixer(outputChannelCount: channelCount, routing: routing)
        try startEngineIfNeeded()
    }

    func adoptOutputDevice(_ deviceUID: String?) -> Bool {
        guard let deviceUID else { return true }
        // Bind only this engine's output unit — do not change the system default.
        let bound = AudioOutputDeviceService.bindOutputDevice(uid: deviceUID, to: engine)
        applyStableMaximumFramesToRender()
        return bound
    }

    /// Connects the mixer to the output. Default stereo routing goes through the output's own
    /// format; wider devices and custom routes connect at the full device width so the mixer
    /// can address every output channel. Resets the master volume to full.
    func connectMixer(outputChannelCount: Int, routing: OutputRoutingSnapshot?) {
        adoptTargetSampleRateIfNeeded()
        engine.mainMixerNode.outputVolume = 1
        engine.disconnectNodeOutput(mixerNode)
        engine.disconnectNodeOutput(engine.mainMixerNode)

        let needsWideOutput = outputChannelCount > 2 || routing?.hasNonDefaultRouting == true
        if needsWideOutput, let wideFormat = AudioOutputDeviceService.multiChannelFormat(
            sampleRate: outputSampleRate,
            channelCount: max(outputChannelCount, 2)
        ) {
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: wideFormat)
            engine.connect(mixerNode, to: engine.mainMixerNode, format: wideFormat)
            mixerOutputChannelCount = Int(wideFormat.channelCount)
        } else {
            let outputFormat = engine.outputNode.outputFormat(forBus: 0)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
            engine.connect(mixerNode, to: engine.mainMixerNode, format: stemMixer.format)
            mixerOutputChannelCount = 2
        }
        publishMixerLayout()
    }

    /// Tells the mixer which voices to render and which output channels each one feeds.
    func publishMixerLayout() {
        let routing = routingSnapshot
        let width = mixerOutputChannelCount
        var entries = tracks.values.map { track in
            let destination = routing.map { OutputRoutingStore.destination(for: track.groupID, snapshot: $0) }
            return StemMixer.Entry(
                voice: track.memoryPlayer.mixerVoice,
                route: MixerRoute(destination: destination ?? .defaultDestination, outputChannelCount: width)
            )
        }
        let guideDestination = routing.map(OutputRoutingStore.guideDestination(snapshot:))
        entries.append(StemMixer.Entry(
            voice: announcementSource,
            route: MixerRoute(destination: guideDestination ?? .defaultDestination, outputChannelCount: width)
        ))
        stemMixer.setEntries(entries)
    }

    private func outputChannelCount(for routing: OutputRoutingSnapshot) -> Int {
        let deviceCount = AudioOutputDeviceService.channelCount(for: routing.deviceUID)
        return max(routing.channelCount, deviceCount, 2)
    }

    /// Moves the mixer, the tracks and the transport's frame grid to `targetSampleRate`.
    /// Call with the engine stopped: the old mixer node must not render again.
    private func adoptTargetSampleRateIfNeeded() {
        let target = targetSampleRate
        guard target != outputSampleRate else { return }
        assert(!engine.isRunning, "Stop the engine before changing the mixer's rate")
        outputSampleRate = target

        engine.disconnectNodeOutput(mixerNode)
        engine.detach(mixerNode)
        let mixer = StemMixer(sampleRate: target)
        stemMixer = mixer
        mixerNode = mixer.makeSourceNode()
        engine.attach(mixerNode)
        transport.setSampleRate(target)
        rebuildTracksAtOutputSampleRate()
    }

    /// Each track renders at the mixer's rate, so a rate change replaces every player.
    /// The caller re-applies the mix afterwards.
    private func rebuildTracksAtOutputSampleRate() {
        for (id, track) in tracks {
            track.memoryPlayer.invalidateRendering()
            let payload = PreparedTrackPayload(
                id: id,
                buffer: track.memoryPlayer.sampleSource,
                settings: track.settings,
                groupID: track.groupID
            )
            tracks[id] = buildTrackState(for: payload)
        }
        applyLoopPrefetch()
    }
}
