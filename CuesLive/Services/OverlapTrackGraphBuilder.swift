import AVFoundation
import Foundation

enum SongPlaybackArrangementLoader {
    struct Sections {
        let sectionsByTrack: [UUID: [ArrangementDisplaySection]]
        let masterSections: [ArrangementDisplaySection]
    }

    static func sections(for song: Song) -> Sections {
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        let arrangement = projectState.arrangement
        let inputs = PlaybackCoordinator.arrangementLayoutInputs(
            for: song,
            markers: projectState.markers
        )
        let layout = SongArrangementStore.playbackLayoutSnapshot(
            slots: arrangement.slots,
            clipTrims: arrangement.clipTrims,
            removedClips: arrangement.removedClips,
            clipGaps: arrangement.clipGaps,
            clipRegions: arrangement.clipRegions,
            tracks: playbackTracks(for: song),
            inputs: inputs
        )
        return Sections(
            sectionsByTrack: layout.trackSections,
            masterSections: layout.rulerSections
        )
    }

    static func playbackTracks(
        for song: Song
    ) -> [(id: UUID, trimStart: TimeInterval, trimEnd: TimeInterval)] {
        song.sortedTracks.map { track in
            (
                id: track.id,
                trimStart: track.trimStartSeconds,
                trimEnd: track.trimEndSeconds ?? trackSourceDuration(for: track.id, in: song)
            )
        }
    }

    private static func trackSourceDuration(for trackID: UUID, in song: Song) -> TimeInterval {
        guard let track = song.sortedTracks.first(where: { $0.id == trackID }),
              let url = FileStore.trackURL(for: song, track: track) else {
            return 1
        }
        return FileStore.fileDuration(at: url) ?? 1
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

    static func arrangementMapper(
        settings: AudioEngineManager.TrackSettings,
        sections: [ArrangementDisplaySection],
        fileDuration: TimeInterval
    ) -> ArrangementTimelineMapper {
        ArrangementTimelineMapper(
            sections: settings.bypassesArrangementMapping ? [] : sections,
            trimStart: settings.trimStart,
            trimEnd: settings.trimEnd ?? fileDuration,
            usesArrangement: !settings.bypassesArrangementMapping && !sections.isEmpty
        )
    }

    static func buildTrack(
        payload: AudioEngineManager.PreparedTrackPayload,
        sections: [ArrangementDisplaySection],
        transport: AudioPlaybackTransport,
        engine: AVAudioEngine
    ) throws -> BuiltTrack {
        let resolved = resolvedSettings(for: payload)
        let mapper = arrangementMapper(
            settings: resolved.settings,
            sections: sections,
            fileDuration: resolved.fileDuration
        )

        let memoryPlayer = TrackMemoryPlayer(
            trackID: payload.id,
            buffer: payload.buffer,
            transport: transport,
            mapper: mapper
        )

        let timePitchNode = AVAudioUnitTimePitch()
        timePitchNode.pitch = resolved.settings.pitchCents
        timePitchNode.rate = 1.0
        timePitchNode.auAudioUnit.shouldBypassEffect = abs(resolved.settings.pitchCents) < 0.5

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
