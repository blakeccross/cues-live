import CryptoKit
import Foundation
import SwiftData

enum RemoteSessionSnapshotBuilder {
    @MainActor
    static func makeSnapshot(
        setlist: Setlist,
        coordinator: PlaybackCoordinator,
        context: ModelContext,
        hostDisplayName: String,
        sectionLoop: SectionLoopController,
        groupMixFade: GroupMixFadeController,
        cuedSectionID: UUID?,
        cueFireTime: TimeInterval?
    ) -> RemoteSessionSnapshot {
        var entries: [RemoteSetlistEntryDTO] = []
        var songsByID: [UUID: RemoteSongDTO] = [:]
        var playbackIndex = 0

        for entry in setlist.sortedEntries {
            let entryID = stableEntryID(for: entry)
            if let header = entry.headerTitle, entry.song == nil {
                entries.append(
                    RemoteSetlistEntryDTO(
                        id: entryID,
                        sortOrder: entry.sortOrder,
                        headerTitle: header,
                        songID: nil,
                        transition: entry.transition.rawValue,
                        playbackIndex: nil
                    )
                )
                continue
            }

            guard let song = entry.song else { continue }
            if songsByID[song.id] == nil {
                songsByID[song.id] = makeSongDTO(song: song, coordinator: coordinator)
            }
            entries.append(
                RemoteSetlistEntryDTO(
                    id: entryID,
                    sortOrder: entry.sortOrder,
                    headerTitle: nil,
                    songID: song.id,
                    transition: entry.transition.rawValue,
                    playbackIndex: playbackIndex
                )
            )
            playbackIndex += 1
        }

        let groups = TrackGroupStore.sortedGroups(from: context).map { group in
            RemoteGroupDTO(
                id: group.id,
                name: group.name,
                sortOrder: group.sortOrder,
                volume: group.volume,
                isMuted: group.isMuted,
                isMixable: !TimecodePlaybackSupport.isTimecodeGroup(group),
                paletteKey: group.paletteKey
            )
        }
        let state = makeState(
            coordinator: coordinator,
            context: context,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime
        )

        return RemoteSessionSnapshot(
            protocolVersion: RemoteSessionBonjour.protocolVersion,
            hostDisplayName: hostDisplayName,
            setlistID: setlist.id,
            setlistName: setlist.name,
            entries: entries,
            songs: Array(songsByID.values),
            librarySongs: makeLibrarySongs(context: context),
            groups: groups,
            state: state
        )
    }

    @MainActor
    private static func makeLibrarySongs(context: ModelContext) -> [RemoteLibrarySongDTO] {
        let descriptor = FetchDescriptor<Song>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let songs = (try? context.fetch(descriptor)) ?? []
        return songs.map { song in
            RemoteLibrarySongDTO(
                id: song.id,
                name: song.name,
                bpm: song.bpm,
                trackCount: song.tracks.count,
                createdAt: song.createdAt
            )
        }
    }

    @MainActor
    static func makeState(
        coordinator: PlaybackCoordinator,
        context: ModelContext,
        sectionLoop: SectionLoopController,
        groupMixFade: GroupMixFadeController,
        cuedSectionID: UUID?,
        cueFireTime: TimeInterval?
    ) -> RemoteSessionState {
        let mix = GroupMixStore.snapshot(in: context)
        var groupVolumes: [String: Double] = [:]
        for (id, volume) in mix.volumeByGroupID {
            groupVolumes[id.uuidString] = Double(volume)
        }

        let playhead: TimeInterval = coordinator.isPlaying
            ? coordinator.livePlayheadTime()
            : coordinator.currentTime
        let transport = transportTexts(for: coordinator, at: playhead)

        return RemoteSessionState(
            currentIndex: coordinator.currentIndex,
            currentSongID: coordinator.currentSong?.id,
            isPlaying: coordinator.isPlaying,
            isAudiblePlaying: coordinator.isAudiblePlaying,
            isLoaded: coordinator.isLoaded || coordinator.currentSong != nil,
            isLoadingSong: coordinator.isLoadingSong,
            loadError: coordinator.loadError,
            currentTime: finiteTime(playhead),
            duration: finiteTime(
                coordinator.currentWaveformSnapshot?.timelineDuration
                    ?? coordinator.currentSong.map { TimecodePlaybackSupport.timelineDuration(for: $0) }
                    ?? 0
            ),
            bpmText: transport.bpm,
            meterText: transport.meter,
            keyText: transport.key,
            positionText: transport.position,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime.map(finiteTime),
            isLooping: sectionLoop.isLooping,
            activeLoopSectionID: sectionLoop.activeSectionID,
            manualLoopSectionID: sectionLoop.manualSectionID,
            isFadedOut: groupMixFade.isFadedOut,
            isFading: groupMixFade.isFading,
            groupVolumes: groupVolumes,
            mutedGroupIDs: Array(mix.mutedGroupIDs),
            ungroupedVolume: Double(mix.ungroupedVolume).isFinite ? Double(mix.ungroupedVolume) : 1,
            ungroupedIsMuted: mix.ungroupedIsMuted
        )
    }

    private static func finiteTime(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }

    @MainActor
    private static func makeSongDTO(
        song: Song,
        coordinator: PlaybackCoordinator
    ) -> RemoteSongDTO {
        let snapshot = coordinator.resolveWaveformSnapshot(for: song)
        let fallbackDuration = TimecodePlaybackSupport.timelineDuration(for: song)
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)

        let sections: [RemoteArrangementSectionDTO]
        let peakSections: [RemoteArrangementSectionDTO]
        let loopSlotIDs: [UUID]
        let tempoChanges: [TempoChange]
        let timeSignatureChanges: [TimeSignatureChange]

        if let snapshot {
            sections = snapshot.sections.map(RemoteArrangementSectionDTO.init)
            peakSections = snapshot.peakSections.map(RemoteArrangementSectionDTO.init)
            loopSlotIDs = Array(snapshot.loopSlotIDs)
            tempoChanges = snapshot.tempoChanges.isEmpty ? projectState.tempoChanges : snapshot.tempoChanges
            timeSignatureChanges = snapshot.timeSignatureChanges.isEmpty
                ? projectState.timeSignatureChanges
                : snapshot.timeSignatureChanges
        } else {
            sections = []
            peakSections = []
            loopSlotIDs = []
            tempoChanges = projectState.tempoChanges
            timeSignatureChanges = projectState.timeSignatureChanges
        }

        let duration = max(snapshot?.timelineDuration ?? fallbackDuration, 0.001)
        let peaks = peaksForRemoteTransfer(snapshot: snapshot)

        return RemoteSongDTO(
            id: song.id,
            name: song.name,
            fileDuration: snapshot?.fileDuration ?? fallbackDuration,
            timelineDuration: duration,
            key: song.transportKeyText,
            sections: sections,
            peakSections: peakSections,
            loopSlotIDs: loopSlotIDs,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            showsMeasureGrid: snapshot?.showsMeasureGrid ?? (song.bpm != nil),
            peaks: peaks
        )
    }

    /// Max samples shipped per song over the remote session (file-time summed peaks).
    private static let remotePeakBudget = 2048

    @MainActor
    private static func peaksForRemoteTransfer(snapshot: LiveSongWaveformSnapshot?) -> [Float] {
        guard let snapshot, !snapshot.trackSources.isEmpty else { return [] }
        guard let peaks = WaveformCache.shared.cachedSummedPeaks(for: snapshot.trackSources),
              !peaks.isEmpty else {
            return []
        }
        return downsamplePeaks(peaks, maxCount: remotePeakBudget)
    }

    private static func downsamplePeaks(_ peaks: [Float], maxCount: Int) -> [Float] {
        guard maxCount > 0, peaks.count > maxCount else { return peaks }

        var result = [Float](repeating: 0, count: maxCount)
        let ratio = Double(peaks.count) / Double(maxCount)
        for index in 0..<maxCount {
            let start = Int(Double(index) * ratio)
            let end = min(peaks.count, max(start + 1, Int(Double(index + 1) * ratio)))
            result[index] = peaks[start..<end].max() ?? 0
        }
        return result
    }

    static func stableEntryID(for entry: SetlistEntry) -> UUID {
        let seed = String(describing: entry.persistentModelID)
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @MainActor
    private static func transportTexts(
        for coordinator: PlaybackCoordinator,
        at time: TimeInterval
    ) -> TransportStatusSnapshot {
        guard let song = coordinator.currentSong else {
            return TransportStatusSnapshot(position: "- - -", bpm: "-", meter: "-", key: "-")
        }

        let snapshot = coordinator.waveformSnapshot(for: song)
        let tempoChanges: [TempoChange] = {
            if let changes = snapshot?.tempoChanges, !changes.isEmpty { return changes }
            return [TempoChange(startMeasure: 1, bpm: song.bpm ?? TempoChange.defaultBPM)]
        }()
        let timeSignatureChanges: [TimeSignatureChange] = {
            if let changes = snapshot?.timeSignatureChanges, !changes.isEmpty { return changes }
            return [
                TimeSignatureChange(
                    numerator: song.timeSignatureNumerator ?? TimeSignatureChange.defaultNumerator,
                    denominator: song.timeSignatureDenominator ?? TimeSignatureChange.defaultDenominator,
                    startMeasure: 1
                )
            ]
        }()

        let position = MeasureTiming.position(
            at: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let measure = position.bar
        let signature = MeasureTiming.numeratorDenominatorForMeasure(
            measure,
            changes: timeSignatureChanges
        )
        let bpm = MeasureTiming.activeBPM(
            at: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        return TransportStatusSnapshot(
            position: MeasureTiming.formatTransportPosition(position),
            bpm: String(format: "%.1f", bpm),
            meter: "\(signature.numerator)/\(signature.denominator)",
            key: song.transportKeyText
        )
    }
}
