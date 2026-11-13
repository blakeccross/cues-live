import Foundation
import Observation
import SwiftData

@Observable
final class SongEditorViewModel {
    private let audioEngine = AudioEngineManager.shared
    /// Set when the editor follows live setlist playback instead of owning the engine.
    private let setlist: PlaybackCoordinator?

    let song: Song
    private(set) var loadError: String?
    private(set) var isLoaded = false
    private(set) var isReloadingSong = false
    private var trackDurations: [UUID: TimeInterval] = [:]
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var modelContext: ModelContext?

    /// - Parameter setlist: When set, playback stays with the setlist and edits apply to
    ///   its engine while it has this song loaded. Transport calls are ignored.
    init(song: Song, followingSetlist setlist: PlaybackCoordinator? = nil) {
        self.song = song
        self.setlist = setlist
    }

    var followsSetlist: Bool {
        setlist != nil
    }

    /// Whether the shared engine's playhead belongs to this song. False when the editor
    /// follows a setlist that is on another song, so the editor hides that playhead.
    var isActiveSetlistSong: Bool {
        guard let setlist else { return true }
        return setlist.currentSong?.id == song.id
    }

    /// The engine edits apply to: the setlist's audible engine, or the shared one this editor owns.
    private var engine: AudioEngineManager {
        setlist?.playbackEngine ?? audioEngine
    }

    /// False while following a setlist that has another song (or nothing) loaded.
    /// A standalone editor always targets its own engine.
    private var ownsLoadedSong: Bool {
        guard let setlist else { return true }
        return setlist.hasLoadedSong(song.id)
    }

    /// Loads the song for playback. When following a setlist the engine already has it,
    /// so only later calls (after tracks change) reload it there.
    func loadSong(context: ModelContext) {
        modelContext = context
        if let setlist {
            if isLoaded {
                setlist.reloadEditedSong(song.id)
            }
            isLoaded = true
            loadError = nil
            return
        }
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
        if let setlist {
            setlist.reloadEditedSong(song.id)
            return
        }
        reloadSong()
    }

    /// Saves the song's key and shifts each included stem live; nothing is rendered.
    func applyKeyChange(context: ModelContext) throws {
        try context.save()
        try SongProjectBridge.syncProjectFile(for: song, context: context)
        guard ownsLoadedSong else { return }
        for track in song.sortedTracks {
            engine.updateTrackSettings(id: track.id, settings: AudioEngineManager.TrackSettings(track: track))
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
                try audioEngine.loadPreparedTracks(payloads, routing: currentRoutingSnapshot())
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
        guard isLoaded, !followsSetlist else { return }
        audioEngine.play()
    }

    func pause() {
        guard !followsSetlist else { return }
        audioEngine.pause()
    }

    func stop() {
        guard !followsSetlist else { return }
        audioEngine.stop()
    }

    func seekAndPlay(to time: TimeInterval) {
        guard isLoaded, !followsSetlist else { return }
        let wasPlaying = audioEngine.isPlaying
        audioEngine.seek(to: time)
        if !wasPlaying {
            audioEngine.play()
        }
    }

    func scheduleSectionTransition(to markerStart: TimeInterval, at transitionTime: TimeInterval) {
        guard isLoaded, !followsSetlist else { return }
        audioEngine.scheduleTransition(to: markerStart, at: transitionTime)
    }

    func cancelScheduledSectionTransition() {
        guard !followsSetlist else { return }
        audioEngine.cancelScheduledTransition()
    }

    func snapToScheduledSection(_ markerStart: TimeInterval) {
        guard !followsSetlist else { return }
        audioEngine.snapToTransitionTarget(markerStart)
    }

    func updateMix(for track: AudioTrack, context: ModelContext) {
        if ownsLoadedSong {
            engine.updateTrackSettings(id: track.id, settings: AudioEngineManager.TrackSettings(track: track))
            engine.applyAllMixSettings()
        }
        try? context.save()
    }

    func updateGroup(for track: AudioTrack, context: ModelContext) {
        TrackGroupStore.reorderTracksByGroup(in: song, context: context)
        refreshTrackOutputGroups()
        try? context.save()
    }

    /// The setlist screen applies routing to its own engine, so a following editor skips this.
    func applyOutputRoutingChange() {
        guard isLoaded, !followsSetlist, let routing = currentRoutingSnapshot() else { return }
        pushTrackGroupsToEngine()
        audioEngine.applyOutputRoutingKeepingTracks(routing)
    }

    /// Pushes group assignments into the loaded players and rewires when show routing is active.
    func refreshTrackOutputGroups() {
        guard ownsLoadedSong else { return }
        pushTrackGroupsToEngine()
        engine.reapplyOutputRoutingIfNeeded()
    }

    private func pushTrackGroupsToEngine() {
        for track in song.sortedTracks {
            engine.updateTrackGroup(id: track.id, groupID: track.group?.id)
        }
    }

    /// Show routing, so the editor honours the same per-group destinations as the setlist.
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
        if let setlist {
            setlist.applyEditedArrangement(timeline, songID: song.id)
            return
        }
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
        if let setlist {
            setlist.applyEditedTempoMap(
                normalizedTempo,
                timeSignatureChanges: normalizedSignatures,
                songID: song.id
            )
            return
        }
        audioEngine.setTempoMap(
            normalizedTempo,
            timeSignatureChanges: normalizedSignatures
        )
    }

    func configureMIDI(events: [MIDIScheduler.ScheduledEvent]) {
        if let setlist {
            setlist.applyEditedMIDI(events, songID: song.id)
            return
        }
        audioEngine.configureMIDI(events: events)
    }
}
