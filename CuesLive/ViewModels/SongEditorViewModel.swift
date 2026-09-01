import Foundation
import Observation
import SwiftData

@Observable
final class SongEditorViewModel {
    private typealias CachedDecodedTrack = SongTrackLoader.CachedDecodedTrack

    private let audioEngine = AudioEngineManager.shared

    let song: Song
    private(set) var loadError: String?
    private(set) var isLoaded = false
    private(set) var isReloadingSong = false
    private var trackDurations: [UUID: TimeInterval] = [:]
    private var decodedBufferCache: [UUID: CachedDecodedTrack] = [:]
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var modelContext: ModelContext?

    init(song: Song) {
        self.song = song
    }

    func loadSong(context: ModelContext) {
        modelContext = context
        claimEngineForSongEditing()
        reloadSong()
    }

    /// Detaches live setlist playback from the shared engine so editing owns it.
    private func claimEngineForSongEditing() {
        audioEngine.onPlaybackFinished = nil
        audioEngine.applyGroupMix(.default)
        audioEngine.pause()
    }

    func applyKeyChange(context: ModelContext, highQuality: Bool) async {
        let wasHighQuality = song.transposeHighQuality
        song.transposeHighQuality = highQuality
        try? context.save()

        if highQuality || wasHighQuality {
            reloadTask?.cancel()
            await performReload()
            return
        }

        applyRealtimePitch()
    }

    private func applyRealtimePitch() {
        guard isLoaded else { return }

        for track in song.sortedTracks {
            audioEngine.updateTrackSettings(
                id: track.id,
                settings: AudioEngineManager.TrackSettings(track: track)
            )
        }
    }

    private func reloadSong() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            await performReload()
        }
    }

    /// Reloads stems after media changes such as generating a click track.
    func reloadSongAfterMediaChange() {
        reloadSong()
    }

    @MainActor
    private func performReload() async {
        claimEngineForSongEditing()
        audioEngine.stop()
        reloadGeneration += 1
        let generation = reloadGeneration
        isReloadingSong = true
        defer {
            if generation == reloadGeneration {
                isReloadingSong = false
                reloadTask = nil
            }
        }

        let trackInputs = song.sortedTracks.compactMap { track -> (
            id: UUID,
            url: URL,
            relativePath: String,
            settings: AudioEngineManager.TrackSettings,
            groupID: UUID?
        )? in
            guard let url = FileStore.trackURL(for: song, track: track) else { return nil }
            return (
                id: track.id,
                url: url,
                relativePath: track.mediaPath ?? track.relativeFilePath,
                settings: AudioEngineManager.TrackSettings(track: track),
                groupID: track.group?.id
            )
        }

        guard !trackInputs.isEmpty else {
            isLoaded = false
            loadError = "Import at least one track to preview this song."
            return
        }

        audioEngine.stop()
        pruneDecodedBufferCache()
        TrackBakeCache.shared.prune(activeTrackIDs: Set(trackInputs.map(\.id)))

        let bakePitchShift = song.transposeHighQuality

        let preparationResult: Result<[AudioEngineManager.PreparedTrackPayload], Error>
        if bakePitchShift {
            let sourceModificationDates = SongTrackLoader.sourceModificationDates(for: trackInputs)

            let decodedBuffers: [UUID: DecodedStemBuffer]
            do {
                decodedBuffers = try await SongTrackLoader.decodeTracks(
                    inputs: trackInputs,
                    sourceModificationDates: sourceModificationDates,
                    decodedBufferCache: decodedBufferCache
                )
                for input in trackInputs {
                    guard let buffer = decodedBuffers[input.id] else { continue }
                    let modificationDate = sourceModificationDates[input.id] ?? .distantPast
                    decodedBufferCache[input.id] = CachedDecodedTrack(
                        relativePath: input.relativePath,
                        sourceModificationDate: modificationDate,
                        buffer: buffer
                    )
                }
            } catch {
                isLoaded = false
                loadError = error.localizedDescription
                return
            }

            preparationResult = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(
                        try await SongTrackLoader.prepareTrackPayloads(
                            inputs: trackInputs,
                            decodedBuffers: decodedBuffers,
                            sourceModificationDates: sourceModificationDates,
                            bakePitchShift: true
                        )
                    )
                } catch {
                    return .failure(error)
                }
            }.value
        } else {
            preparationResult = Result {
                try SongTrackLoader.streamingPayloads(trackInputs: trackInputs)
            }
        }

        guard generation == reloadGeneration, !Task.isCancelled else { return }

        switch preparationResult {
        case .success(let prepared):
            trackDurations = [:]
            for payload in prepared {
                trackDurations[payload.id] = Double(payload.buffer.frameCount) / payload.buffer.sampleRate
            }

            let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
            let tempoChanges = projectState.tempoChanges
            let timeSignatureChanges = projectState.timeSignatureChanges

            do {
                var payloads = prepared
                try appendTimecodePayloadIfNeeded(to: &payloads)
                try audioEngine.loadPreparedTracks(payloads)
                isLoaded = true
                loadError = nil
                syncTempoMap(tempoChanges, timeSignatureChanges: timeSignatureChanges)
            } catch {
                isLoaded = false
                loadError = error.localizedDescription
            }

        case .failure(let error):
            isLoaded = false
            if error is CancellationError {
                loadError = nil
            } else {
                loadError = error.localizedDescription
            }
        }
    }

    private func appendTimecodePayloadIfNeeded(
        to payloads: inout [AudioEngineManager.PreparedTrackPayload]
    ) throws {
        guard let modelContext else { return }
        let settings = TimecodeSettingsStore.snapshot(in: modelContext)
        guard settings.isEnabled else { return }

        let duration = TimecodePlaybackSupport.timelineDuration(for: song)
        let groupID = TimecodePlaybackSupport.resolveGroupID(in: modelContext)
        try TimecodePlaybackSupport.appendPayloadIfNeeded(
            to: &payloads,
            settings: settings,
            songIndex: 0,
            priorSongDurations: [],
            duration: duration,
            groupID: groupID
        )
    }

    func play() {
        guard isLoaded else { return }
        audioEngine.play()
    }

    func pause() {
        audioEngine.pause()
    }

    func stop() {
        audioEngine.stop()
    }

    func seekAndPlay(to time: TimeInterval) {
        guard isLoaded else { return }
        let wasPlaying = audioEngine.isPlaying
        audioEngine.seek(to: time)
        if !wasPlaying {
            audioEngine.play()
        }
    }

    func scheduleSectionTransition(to markerStart: TimeInterval, at transitionTime: TimeInterval) {
        guard isLoaded else { return }
        audioEngine.scheduleTransition(to: markerStart, at: transitionTime)
    }

    func cancelScheduledSectionTransition() {
        audioEngine.cancelScheduledTransition()
    }

    func snapToScheduledSection(_ markerStart: TimeInterval) {
        audioEngine.snapToTransitionTarget(markerStart)
    }

    func updateMix(for track: AudioTrack, context: ModelContext) {
        audioEngine.updateTrackSettings(id: track.id, settings: AudioEngineManager.TrackSettings(track: track))
        audioEngine.applyAllMixSettings()
        try? context.save()
    }

    func updateTrim(for track: AudioTrack, context: ModelContext) {
        audioEngine.updateTrackSettings(id: track.id, settings: AudioEngineManager.TrackSettings(track: track))
        try? context.save()
    }

    func updateGroup(for track: AudioTrack, context: ModelContext) {
        TrackGroupStore.reorderTracksByGroup(in: song, context: context)
        try? context.save()
    }

    @discardableResult
    func autoAssignGroups(groups: [TrackGroup], context: ModelContext) -> Int {
        let assignedCount = TrackGroupStore.autoAssignGroups(
            for: song.sortedTracks,
            groups: groups,
            in: context
        )
        TrackGroupStore.reorderTracksByGroup(in: song, context: context)
        return assignedCount
    }

    func previewTrim(for track: AudioTrack) {
        audioEngine.updateTrackSettings(id: track.id, settings: AudioEngineManager.TrackSettings(track: track))
        audioEngine.stop()
        audioEngine.play()
    }

    func preloadTrackDurations() {
        for track in song.sortedTracks {
            guard trackDurations[track.id] == nil else { continue }
            guard let url = FileStore.trackURL(for: song, track: track) else { continue }
            trackDurations[track.id] = FileStore.fileDuration(at: url) ?? 0
        }
    }

    func fileDuration(for track: AudioTrack) -> TimeInterval {
        if let cached = trackDurations[track.id] {
            return cached
        }
        guard let url = FileStore.trackURL(for: song, track: track) else { return 0 }
        let duration = FileStore.fileDuration(at: url) ?? 0
        trackDurations[track.id] = duration
        return duration
    }

    func setArrangement(
        sectionsByTrack: [UUID: [ArrangementDisplaySection]],
        masterSections: [ArrangementDisplaySection],
        removedClips: [ArrangementRemovedClip] = []
    ) {
        guard isLoaded else { return }
        audioEngine.setArrangement(
            sectionsByTrack: sectionsByTrack,
            masterSections: masterSections,
            removedClips: removedClips
        )
    }

    func applyArrangementLayout(
        _ layout: ArrangementLayoutSnapshot,
        removedClips: [ArrangementRemovedClip]
    ) {
        guard isLoaded else { return }
        setArrangement(
            sectionsByTrack: layout.trackSections,
            masterSections: layout.rulerSections,
            removedClips: removedClips
        )
    }

    func syncTrackArrangement(
        trackID: UUID,
        markers: [ArrangementMarker],
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = [],
        track: AudioTrack? = nil
    ) {
        guard isLoaded else { return }

        let inputs = arrangementLayoutInputs(markers: markers)
        let resolvedTrack = track ?? song.sortedTracks.first(where: { $0.id == trackID })
        let trimEnd = resolvedTrack.map { $0.trimEndSeconds ?? fileDuration(for: $0) }
            ?? inputs.sourceDurationForTrack(trackID)
        let trimStart = resolvedTrack?.trimStartSeconds ?? 0

        let sections = SongArrangementStore.playbackTrackSections(
            for: trackID,
            trimStart: trimStart,
            trimEnd: trimEnd,
            slots: slots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            inputs: inputs
        )
        audioEngine.updateTrackArrangement(
            trackID: trackID,
            sections: sections,
            removedClips: removedClips
        )
    }

    func buildArrangementLayout(
        markers: [ArrangementMarker],
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = []
    ) -> ArrangementLayoutSnapshot {
        SongArrangementStore.buildLayoutSnapshot(
            slots: slots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            inputs: arrangementLayoutInputs(markers: markers)
        )
    }

    func buildPlaybackLayout(
        markers: [ArrangementMarker],
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = []
    ) -> ArrangementLayoutSnapshot {
        let inputs = arrangementLayoutInputs(markers: markers)
        let tracks = song.sortedTracks.map { track in
            (
                id: track.id,
                trimStart: track.trimStartSeconds,
                trimEnd: track.trimEndSeconds ?? fileDuration(for: track)
            )
        }
        return SongArrangementStore.playbackLayoutSnapshot(
            slots: slots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            tracks: tracks,
            inputs: inputs
        )
    }

    func syncArrangement(
        markers: [ArrangementMarker],
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = []
    ) {
        guard isLoaded else { return }
        applyArrangementLayout(
            buildPlaybackLayout(
                markers: markers,
                slots: slots,
                clipTrims: clipTrims,
                removedClips: removedClips,
                clipGaps: clipGaps,
                clipRegions: clipRegions
            ),
            removedClips: removedClips
        )
    }

    func syncTempoMap(
        _ tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) {
        guard isLoaded else { return }
        let normalizedTempo = tempoChanges.normalizedEnsuringInitialMarker(
            defaultBPM: song.bpm ?? TempoChange.defaultBPM
        )
        let normalizedSignatures = timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator,
            defaultDenominator: song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
        )
        audioEngine.setTempoMap(
            normalizedTempo,
            referenceBPM: normalizedTempo.referenceBPM,
            timeSignatureChanges: normalizedSignatures
        )
    }

    private func arrangementLayoutInputs(markers: [ArrangementMarker]) -> ArrangementLayoutInputs {
        SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: song.sortedTracks.map(\.id),
            sourceDurationForTrack: { [self] trackID in
                guard let track = song.sortedTracks.first(where: { $0.id == trackID }) else { return 1 }
                return fileDuration(for: track)
            }
        )
    }

    private func pruneDecodedBufferCache() {
        let activeTrackIDs = Set(song.sortedTracks.map(\.id))
        decodedBufferCache = decodedBufferCache.filter { activeTrackIDs.contains($0.key) }
    }
}
