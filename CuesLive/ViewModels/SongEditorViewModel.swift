import Foundation
import Observation
import SwiftData

@Observable
final class SongEditorViewModel {
    private let audioEngine = AudioEngineManager.shared

    let song: Song
    private(set) var loadError: String?
    private(set) var isLoaded = false
    private(set) var isReloadingSong = false
    private var trackDurations: [UUID: TimeInterval] = [:]
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var modelContext: ModelContext?
    /// Set once the editor has applied show routing, so a later reload keeps it.
    private var monitorsOutputRouting = false

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

    /// Saves the song's key and shifts each included stem live; nothing is rendered.
    func applyKeyChange(context: ModelContext) throws {
        try context.save()
        try SongProjectBridge.syncProjectFile(for: song, context: context)
        for track in song.sortedTracks {
            audioEngine.updateTrackSettings(id: track.id, settings: AudioEngineManager.TrackSettings(track: track))
        }
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

        let trackInputs: [SongTrackLoader.TrackInput]
        do {
            trackInputs = try SongTrackLoader.trackInputs(for: song)
        } catch {
            isLoaded = false
            loadError = error.localizedDescription
            return
        }

        guard !trackInputs.isEmpty else {
            isLoaded = false
            loadError = "Import at least one track to preview this song."
            return
        }

        audioEngine.stop()

        let preparationResult = Result {
            try SongTrackLoader.streamingPayloads(trackInputs: trackInputs)
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
                try audioEngine.loadPreparedTracks(payloads, routing: editorRoutingSnapshot())
                isLoaded = true
                loadError = nil
                // Loading clears the engine's arrangement. Restore it here rather than
                // relying on the view to notice the reload: a reload that never suspends
                // flips `isReloadingSong` within one update, so the view sees no change and
                // every track would play its file straight through, ignoring clips and tempo.
                syncArrangement(projectState.timeline)
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

    func updateGroup(for track: AudioTrack, context: ModelContext) {
        TrackGroupStore.reorderTracksByGroup(in: song, context: context)
        refreshTrackOutputGroups()
        try? context.save()
    }

    func applyOutputRoutingChange() {
        guard let routing = currentRoutingSnapshot() else { return }
        monitorsOutputRouting = true
        guard isLoaded else { return }
        pushTrackGroupsToEngine()
        audioEngine.applyOutputRoutingKeepingTracks(routing)
    }

    /// Pushes group assignments into the loaded players and rewires when show routing is active.
    func refreshTrackOutputGroups() {
        pushTrackGroupsToEngine()
        audioEngine.reapplyOutputRoutingIfNeeded()
    }

    private func pushTrackGroupsToEngine() {
        for track in song.sortedTracks {
            audioEngine.updateTrackGroup(id: track.id, groupID: track.group?.id)
        }
    }

    /// `nil` until the editor has applied an output change, so opening a song still
    /// monitors through the master mixer.
    private func editorRoutingSnapshot() -> OutputRoutingSnapshot? {
        guard monitorsOutputRouting else { return nil }
        return currentRoutingSnapshot()
    }

    private func currentRoutingSnapshot() -> OutputRoutingSnapshot? {
        guard let modelContext else { return nil }
        let deviceUID = OutputRoutingStore.config(in: modelContext).selectedDeviceUID
        let channelCount = AudioOutputDeviceService.channelCount(for: deviceUID)
        return OutputRoutingStore.snapshot(in: modelContext, channelCount: channelCount)
    }

    @discardableResult
    func autoAssignGroups(groups: [TrackGroup], context: ModelContext) -> Int {
        let assignedCount = TrackGroupStore.autoAssignGroups(
            for: song.sortedTracks,
            groups: groups,
            in: context
        )
        TrackGroupStore.reorderTracksByGroup(in: song, context: context)
        refreshTrackOutputGroups()
        return assignedCount
    }

    func preloadTrackDurations() {
        for track in song.sortedTracks {
            guard trackDurations[track.id] == nil else { continue }
            trackDurations[track.id] = FileStore.sourceDuration(for: song, track: track) ?? 0
        }
    }

    func fileDuration(for track: AudioTrack) -> TimeInterval {
        if let cached = trackDurations[track.id] {
            return cached
        }
        let duration = FileStore.sourceDuration(for: song, track: track) ?? 0
        trackDurations[track.id] = duration
        return duration
    }

    func syncArrangement(_ timeline: SongTimeline) {
        guard isLoaded else { return }
        audioEngine.setArrangement(SongPlaybackLayout(timeline: timeline))
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
            timeSignatureChanges: normalizedSignatures
        )
    }
}
