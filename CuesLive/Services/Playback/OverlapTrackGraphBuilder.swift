import AVFoundation
import Foundation

enum SongPlaybackLayoutLoader {
    static func layout(for song: Song) -> SongPlaybackLayout {
        SongPlaybackLayout(timeline: SongProjectBridge.projectStateOrDefaults(for: song).timeline)
    }
}

enum OverlapTrackGraphBuilder {
    struct BuiltTrack {
        let trackID: UUID
        let memoryPlayer: TrackMemoryPlayer
        let timePitchNode: AVAudioUnitTimePitch
        let settings: AudioEngineManager.TrackSettings
        let fileDuration: TimeInterval
        let groupID: UUID?
        let sourceFormat: AVAudioFormat

        var playbackOutputNode: AVAudioNode {
            timePitchNode
        }
    }

    static func resolvedSettings(
        for payload: AudioEngineManager.PreparedTrackPayload
    ) -> (settings: AudioEngineManager.TrackSettings, fileDuration: TimeInterval) {
        var settings = payload.settings
        let fileDuration = Double(payload.buffer.frameCount) / payload.buffer.sampleRate
        if settings.trimEnd == nil {
            settings.trimEnd = fileDuration
        }
        return (settings, fileDuration)
    }

    /// Nil clips play the trimmed file linearly.
    static func arrangementMapper(
        settings: AudioEngineManager.TrackSettings,
        clips: [TrackClip]?,
        fileDuration: TimeInterval
    ) -> ArrangementTimelineMapper {
        guard !settings.bypassesArrangementMapping, let clips else {
            return .linear(trimStart: settings.trimStart, trimEnd: settings.trimEnd ?? fileDuration)
        }
        return ArrangementTimelineMapper(clips: clips, fileDuration: fileDuration)
    }

    static func buildTrack(
        payload: AudioEngineManager.PreparedTrackPayload,
        clips: [TrackClip]?,
        transport: AudioPlaybackTransport,
        engine: AVAudioEngine
    ) throws -> BuiltTrack {
        let resolved = resolvedSettings(for: payload)
        let mapper = arrangementMapper(
            settings: resolved.settings,
            clips: clips,
            fileDuration: resolved.fileDuration
        )

        let memoryPlayer = TrackMemoryPlayer(
            trackID: payload.id,
            buffer: payload.buffer,
            transport: transport,
            mapper: mapper
        )

        let timePitchNode = AVAudioUnitTimePitch()
        timePitchNode.pitch = 0
        timePitchNode.rate = 1.0
        timePitchNode.auAudioUnit.shouldBypassEffect = true

        let format = payload.buffer.audioFormat
        engine.attach(memoryPlayer.sourceNode)
        engine.attach(timePitchNode)
        engine.connect(memoryPlayer.sourceNode, to: timePitchNode, format: format)

        return BuiltTrack(
            trackID: payload.id,
            memoryPlayer: memoryPlayer,
            timePitchNode: timePitchNode,
            settings: resolved.settings,
            fileDuration: resolved.fileDuration,
            groupID: payload.groupID,
            sourceFormat: format
        )
    }

    static func connect(_ track: BuiltTrack, to mixer: AVAudioMixerNode, in engine: AVAudioEngine) {
        let node = track.playbackOutputNode
        if node.engine === engine {
            engine.disconnectNodeOutput(node)
        }
        engine.connect(node, to: mixer, format: track.sourceFormat)
    }

    static func connectToMasterMixer(
        playbackOutputNode: AVAudioNode,
        sourceFormat: AVAudioFormat,
        mixer: AVAudioMixerNode,
        in engine: AVAudioEngine
    ) {
        engine.disconnectNodeOutput(playbackOutputNode)
        OutputRoutingManager.clearChannelMap(on: playbackOutputNode)
        engine.connect(playbackOutputNode, to: mixer, format: sourceFormat)
    }

    static func connectToMasterMixer(
        _ track: BuiltTrack,
        mixer: AVAudioMixerNode,
        in engine: AVAudioEngine
    ) {
        connectToMasterMixer(
            playbackOutputNode: track.playbackOutputNode,
            sourceFormat: track.sourceFormat,
            mixer: mixer,
            in: engine
        )
    }

    static func detachPlayerGraph(
        memoryPlayer: TrackMemoryPlayer,
        timePitchNode: AVAudioUnitTimePitch,
        from engine: AVAudioEngine
    ) {
        detachIfAttached(memoryPlayer.sourceNode, from: engine)
        detachIfAttached(timePitchNode, from: engine)
    }

    static func detach(_ track: BuiltTrack, from engine: AVAudioEngine) {
        detachPlayerGraph(
            memoryPlayer: track.memoryPlayer,
            timePitchNode: track.timePitchNode,
            from: engine
        )
    }

    private static func detachIfAttached(_ node: AVAudioNode, from engine: AVAudioEngine) {
        guard node.engine === engine else { return }
        engine.disconnectNodeOutput(node)
        engine.disconnectNodeInput(node)
        engine.detach(node)
    }
}
