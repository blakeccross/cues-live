import Foundation
import Observation
import CoreGraphics
import SwiftData

struct LiveSongWaveformSnapshot: Identifiable {
    let songID: UUID
    let songName: String
    let trackSources: [(url: URL, duration: TimeInterval)]
    let fileDuration: TimeInterval
    let timelineDuration: TimeInterval
    /// Marker columns used for section labels, cueing, and loop badges.
    let sections: [ArrangementDisplaySection]
    /// Playback clip layout used to map timeline time to source audio for the waveform.
    let peakSections: [ArrangementDisplaySection]
    let loopSlotIDs: Set<UUID>
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    /// When false, the setlist lane hides measure ticks (`song.bpm` is unset).
    let showsMeasureGrid: Bool
    /// When set (e.g. remote session or local setlist peak warm), peaks are used
    /// directly and track files are not decoded on the setlist render path.
    let precomputedSourcePeaks: [Float]?

    var id: UUID { songID }

    var contentWidth: CGFloat {
        TimelineLayout.contentWidth(for: timelineDuration, zoom: 1)
    }

    init(
        songID: UUID,
        songName: String,
        trackSources: [(url: URL, duration: TimeInterval)],
        fileDuration: TimeInterval,
        timelineDuration: TimeInterval,
        sections: [ArrangementDisplaySection],
        peakSections: [ArrangementDisplaySection],
        loopSlotIDs: Set<UUID>,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        showsMeasureGrid: Bool,
        precomputedSourcePeaks: [Float]? = nil
    ) {
        self.songID = songID
        self.songName = songName
        self.trackSources = trackSources
        self.fileDuration = fileDuration
        self.timelineDuration = timelineDuration
        self.sections = sections
        self.peakSections = peakSections
        self.loopSlotIDs = loopSlotIDs
        self.tempoChanges = tempoChanges
        self.timeSignatureChanges = timeSignatureChanges
        self.showsMeasureGrid = showsMeasureGrid
        self.precomputedSourcePeaks = precomputedSourcePeaks
    }

    func withPrecomputedPeaks(_ peaks: [Float]?) -> LiveSongWaveformSnapshot {
        LiveSongWaveformSnapshot(
            songID: songID,
            songName: songName,
            trackSources: trackSources,
            fileDuration: fileDuration,
            timelineDuration: timelineDuration,
            sections: sections,
            peakSections: peakSections,
            loopSlotIDs: loopSlotIDs,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            showsMeasureGrid: showsMeasureGrid,
            precomputedSourcePeaks: peaks
        )
    }
}

enum LiveSetlistTimelineItem: Identifiable {
    case header(scrollID: String, title: String)
    case song(songID: UUID, playbackIndex: Int, transitionAfter: SetlistTransition?)

    var id: String {
        switch self {
        case .header(let scrollID, _):
            scrollID
        case .song(_, let playbackIndex, _):
            "song-\(playbackIndex)"
        }
    }
}

@Observable
final class PlaybackCoordinator {
    private var audioEngine = AudioEngineManager.shared
    private let clockEngine = AudioEngineManager.shared
    private var incomingAudioEngine: AudioEngineManager?

    /// Audible engine for the current song. After an overlap handoff this may be a
    /// separate instance from `AudioEngineManager.shared` (the UI clock engine).
    var playbackEngine: AudioEngineManager { audioEngine }

    private(set) var songs: [Song] = []
    private(set) var transitions: [SetlistTransition] = []
    private(set) var overlapConfigs: [OverlapTransitionConfig?] = []
    private(set) var currentIndex = 0
    private(set) var isLoaded = false
    private(set) var isLoadingSong = false
    private(set) var loadError: String?
    private(set) var currentWaveformSnapshot: LiveSongWaveformSnapshot?
    private(set) var timelineItems: [LiveSetlistTimelineItem] = []

    private var loadedSongID: UUID?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var waveformSnapshotPrefetchTask: Task<Void, Never>?
    private var waveformPeakPrefetchTask: Task<Void, Never>?
    private var pendingWaveformPeakJobs: [(songID: UUID, sources: [(url: URL, duration: TimeInterval)])] = []
    private var pendingWaveformSnapshotSongIDs: Set<UUID> = []
    private var waveformSnapshotsBySongID: [UUID: LiveSongWaveformSnapshot] = [:]
    private var prefetchedIncomingPayloads: [AudioEngineManager.PreparedTrackPayload]?
    private var prefetchedIncomingLayout: SongEngineLayout?
    private var prefetchedIncomingSongID: UUID?
    private var incomingPrefetchTask: Task<Void, Never>?
    private var activeOverlapConfig: OverlapTransitionConfig?

    var routingProvider: (() -> OutputRoutingSnapshot)?
    var groupMixProvider: (() -> GroupMixSnapshot)?
    var timecodeSettingsProvider: (() -> TimecodeSettingsSnapshot)?
    var timecodeGroupIDProvider: (() -> UUID?)?

    var currentSong: Song? {
        guard songs.indices.contains(currentIndex) else { return nil }
        return songs[currentIndex]
    }

    var isPlaying: Bool {
        audioEngine.isPlaying
    }

    var currentTime: TimeInterval {
        audioEngine.currentTime
    }

    func livePlayheadTime() -> TimeInterval {
        audioEngine.livePlayheadTime()
    }

    /// Whether any audible playback engine is currently playing.
    /// This is used by UI navigation to decide whether the transport should keep
    /// running when switching songs.
    var isAudiblePlaying: Bool {
        audioEngine.isPlaying || incomingAudioEngine?.isPlaying == true
    }

    var nextSong: Song? {
        let nextIndex = currentIndex + 1
        guard songs.indices.contains(nextIndex) else { return nil }
        return songs[nextIndex]
    }

    var previousSong: Song? {
        let previousIndex = currentIndex - 1
        guard songs.indices.contains(previousIndex) else { return nil }
        return songs[previousIndex]
    }

    var transitionAfterCurrentSong: SetlistTransition? {
        guard transitions.indices.contains(currentIndex) else { return nil }
        return transitions[currentIndex]
    }

    var overlapConfigAfterCurrentSong: OverlapTransitionConfig? {
        guard overlapConfigs.indices.contains(currentIndex) else { return nil }
        return overlapConfigs[currentIndex]
    }

    func song(for id: UUID) -> Song? {
        songs.first { $0.id == id }
    }

    /// Binds this coordinator as the owner of the shared engine's playback callbacks.
    /// Must be called from a stable lifecycle point (not `init`), because SwiftUI
    /// constructs throwaway `@State` default instances on every view re-render,
    /// and an `init`-time assignment would let those throwaways clobber the callback.
    func bindPlaybackHandlers() {
        let handler: (() -> Void) = { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished()
            }
        }

        audioEngine.onPlaybackFinished = handler

        // The shared clock engine is used for cursor/UI time, not for advancing
        // the setlist. If the audible engine is a separate instance, clear the
        // callback from the clock to avoid double-advances after overlap handoffs.
        if clockEngine !== audioEngine {
            clockEngine.onPlaybackFinished = nil
        } else {
            clockEngine.onPlaybackFinished = handler
        }
    }

    func unbindPlaybackHandlers() {
        audioEngine.onPlaybackFinished = nil
        audioEngine.onWillReachEnd = nil
        clockEngine.onPlaybackFinished = nil
        clockEngine.onWillReachEnd = nil
    }

    private func bindPlaybackFinishedHandler() {
        bindPlaybackHandlers()
    }

    @MainActor
    func configure(setlist: Setlist) {
        bindPlaybackFinishedHandler()
        applySetlistEntries(setlist.sortedEntries)
        currentIndex = 0
        prefetchWaveformSnapshots()
        loadCurrentSong()
    }

    @MainActor
    func syncSetlist(_ setlist: Setlist) {
        let currentSongID = currentSong?.id
        applySetlistEntries(setlist.sortedEntries)

        if let currentSongID, let newIndex = songs.firstIndex(where: { $0.id == currentSongID }) {
            currentIndex = newIndex
        } else if songs.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, songs.count - 1)
        }

        // Always warm layout + peaks for the full setlist (covers song add/reorder).
        prefetchWaveformSnapshots()

        if let song = currentSong, song.id == loadedSongID, isLoaded {
            refreshWaveformSnapshots()
            configureOverlapSchedulingIfNeeded()
            return
        }

        loadCurrentSong()
    }

    func updateTransitions(from setlist: Setlist) {
        let currentSongID = currentSong?.id
        applySetlistEntries(setlist.sortedEntries)
        if let currentSongID, let newIndex = songs.firstIndex(where: { $0.id == currentSongID }) {
            currentIndex = newIndex
        }
        if isLoaded {
            configureOverlapSchedulingIfNeeded()
        }
    }

    private func applySetlistEntries(_ entries: [SetlistEntry]) {
        var syncedSongs: [Song] = []
        var syncedTransitions: [SetlistTransition] = []
        var syncedOverlapConfigs: [OverlapTransitionConfig?] = []
        var syncedTimeline: [LiveSetlistTimelineItem] = []

        var songIndex = 0
        for (index, entry) in entries.enumerated() {
            if entry.isHeader {
                syncedTimeline.append(
                    .header(
                        scrollID: "header-\(entry.persistentModelID)",
                        title: entry.headerTitle ?? ""
                    )
                )
            } else if let song = entry.song {
                let hasNextSong = entries[(index + 1)...].contains { $0.song != nil }
                syncedTimeline.append(
                    .song(
                        songID: song.id,
                        playbackIndex: songIndex,
                        transitionAfter: hasNextSong ? entry.transition : nil
                    )
                )
                syncedSongs.append(song)
                syncedTransitions.append(entry.transition)
                syncedOverlapConfigs.append(entry.transition == .overlap ? entry.overlapConfig : nil)
                songIndex += 1
            }
        }

        songs = syncedSongs
        transitions = syncedTransitions
        overlapConfigs = syncedOverlapConfigs
        timelineItems = syncedTimeline
        pruneWaveformSnapshotCache()
    }

    func waveformSnapshot(for song: Song) -> LiveSongWaveformSnapshot? {
        waveformSnapshotsBySongID[song.id]
    }

    /// Returns a cached waveform snapshot, building and storing one synchronously if needed.
    @MainActor
    @discardableResult
    func resolveWaveformSnapshot(for song: Song) -> LiveSongWaveformSnapshot? {
        if let cached = waveformSnapshotsBySongID[song.id] {
            return cached
        }
        guard let snapshot = Self.makeWaveformSnapshot(for: song) else { return nil }
        return storeWaveformSnapshot(snapshot, warmingPeaksIfNeeded: true)
    }

    @MainActor
    func ensureWaveformSnapshot(for song: Song) {
        if waveformSnapshotsBySongID[song.id] != nil { return }
        guard !pendingWaveformSnapshotSongIDs.contains(song.id) else { return }

        pendingWaveformSnapshotSongIDs.insert(song.id)
        Task { @MainActor in
            defer { pendingWaveformSnapshotSongIDs.remove(song.id) }
            guard waveformSnapshotsBySongID[song.id] == nil else { return }
            guard let snapshot = Self.makeWaveformSnapshot(for: song) else { return }
            _ = storeWaveformSnapshot(snapshot, warmingPeaksIfNeeded: true)
        }
    }

    func invalidateWaveformSnapshot(for songID: UUID) {
        waveformSnapshotsBySongID.removeValue(forKey: songID)
        if currentSong?.id == songID {
            currentWaveformSnapshot = nil
        }
    }

    /// Rebuilds setlist waveform layout after song edit and regenerates peaks when
    /// audio sources changed (cache keys include file mtimes).
    @MainActor
    func refreshWaveformAfterEdit(for songID: UUID) {
        invalidateWaveformSnapshot(for: songID)
        guard let song = songs.first(where: { $0.id == songID }) else { return }
        guard let snapshot = Self.makeWaveformSnapshot(for: song) else { return }
        _ = storeWaveformSnapshot(snapshot, warmingPeaksIfNeeded: true)
    }

    private func pruneWaveformSnapshotCache() {
        let activeSongIDs = Set(songs.map(\.id))
        waveformSnapshotsBySongID = waveformSnapshotsBySongID.filter { activeSongIDs.contains($0.key) }
    }

    /// Builds lightweight layout snapshots for every setlist song, then warms
    /// summed peak overviews in the background so returning to setlist is instant.
    @MainActor
    private func prefetchWaveformSnapshots() {
        waveformSnapshotPrefetchTask?.cancel()
        waveformPeakPrefetchTask?.cancel()
        pendingWaveformPeakJobs.removeAll()
        waveformPeakPrefetchTask = nil

        waveformSnapshotPrefetchTask = Task { @MainActor in
            var pendingPeakJobs: [(songID: UUID, sources: [(url: URL, duration: TimeInterval)])] = []

            // Warm the current song first so the active lane paints ASAP.
            let orderedSongs: [Song]
            if let current = currentSong {
                orderedSongs = [current] + songs.filter { $0.id != current.id }
            } else {
                orderedSongs = songs
            }

            for song in orderedSongs {
                if Task.isCancelled { return }
                let snapshot: LiveSongWaveformSnapshot
                if let existing = waveformSnapshotsBySongID[song.id] {
                    snapshot = attachingCachedPeaks(to: existing)
                    if snapshot.precomputedSourcePeaks != existing.precomputedSourcePeaks {
                        waveformSnapshotsBySongID[song.id] = snapshot
                        if song.id == currentSong?.id {
                            currentWaveformSnapshot = snapshot
                        }
                    }
                } else if let built = Self.makeWaveformSnapshot(for: song) {
                    snapshot = storeWaveformSnapshot(built, warmingPeaksIfNeeded: false)
                } else {
                    continue
                }

                if snapshot.precomputedSourcePeaks == nil, !snapshot.trackSources.isEmpty {
                    pendingPeakJobs.append((song.id, snapshot.trackSources))
                }
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            enqueueWaveformPeakWarm(pendingPeakJobs)
        }
    }

    @MainActor
    @discardableResult
    private func storeWaveformSnapshot(
        _ snapshot: LiveSongWaveformSnapshot,
        warmingPeaksIfNeeded: Bool
    ) -> LiveSongWaveformSnapshot {
        let resolved = attachingCachedPeaks(to: snapshot)
        waveformSnapshotsBySongID[resolved.songID] = resolved
        if resolved.songID == currentSong?.id {
            currentWaveformSnapshot = resolved
        }
        if warmingPeaksIfNeeded,
           resolved.precomputedSourcePeaks == nil,
           !resolved.trackSources.isEmpty {
            enqueueWaveformPeakWarm([(resolved.songID, resolved.trackSources)])
        }
        return resolved
    }

    @MainActor
    private func enqueueWaveformPeakWarm(
        _ jobs: [(songID: UUID, sources: [(url: URL, duration: TimeInterval)])]
    ) {
        guard !jobs.isEmpty else { return }
        for job in jobs {
            pendingWaveformPeakJobs.removeAll { $0.songID == job.songID }
            pendingWaveformPeakJobs.append(job)
        }
        startWaveformPeakWarmIfNeeded()
    }

    @MainActor
    private func startWaveformPeakWarmIfNeeded() {
        guard waveformPeakPrefetchTask == nil else { return }
        guard !pendingWaveformPeakJobs.isEmpty else { return }

        waveformPeakPrefetchTask = Task { @MainActor in
            defer { waveformPeakPrefetchTask = nil }

            while !pendingWaveformPeakJobs.isEmpty {
                if Task.isCancelled {
                    pendingWaveformPeakJobs.removeAll()
                    return
                }
                let job = pendingWaveformPeakJobs.removeFirst()
                let peaks = await WaveformCache.shared.summedPeaks(for: job.sources)
                guard !Task.isCancelled else {
                    pendingWaveformPeakJobs.removeAll()
                    return
                }
                guard let existing = waveformSnapshotsBySongID[job.songID],
                      Self.trackSourcesMatch(existing.trackSources, job.sources) else {
                    continue
                }
                let updated = existing.withPrecomputedPeaks(peaks)
                waveformSnapshotsBySongID[job.songID] = updated
                if job.songID == currentSong?.id {
                    currentWaveformSnapshot = updated
                }
            }
        }
    }

    @MainActor
    private func attachingCachedPeaks(
        to snapshot: LiveSongWaveformSnapshot
    ) -> LiveSongWaveformSnapshot {
        if snapshot.precomputedSourcePeaks != nil { return snapshot }
        guard let peaks = WaveformCache.shared.cachedSummedPeaks(for: snapshot.trackSources) else {
            return snapshot
        }
        return snapshot.withPrecomputedPeaks(peaks)
    }

    private static func trackSourcesMatch(
        _ lhs: [(url: URL, duration: TimeInterval)],
        _ rhs: [(url: URL, duration: TimeInterval)]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in lhs.indices {
            if lhs[index].url.path != rhs[index].url.path { return false }
            if abs(lhs[index].duration - rhs[index].duration) > 0.001 { return false }
        }
        return true
    }

    private func handlePlaybackFinished() {
        switch transitionAfterCurrentSong {
        case .continue:
            advanceToNextSong(autoPlay: true)
        case .overlap:
            if incomingAudioEngine != nil, let incoming = nextSong {
                Task { @MainActor in
                    completeActiveOverlapTransition(to: incoming)
                }
            } else {
                advanceToNextSong(autoPlay: true)
            }
        case .stop, .none:
            break
        }
    }

    func loadCurrentSong(autoPlay: Bool = false, preservedTime: TimeInterval? = nil) {
        if let song = currentSong {
            invalidateWaveformSnapshot(for: song.id)
        }
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            await performLoadCurrentSong(autoPlay: autoPlay, preservedTime: preservedTime)
        }
    }

    func play() {
        guard isLoaded, !isLoadingSong else { return }
        if clockEngine !== audioEngine {
            clockEngine.play()
        }
        audioEngine.play()
        incomingAudioEngine?.play()
    }

    func pause() {
        if clockEngine !== audioEngine {
            clockEngine.pause()
        }
        audioEngine.pause()
        incomingAudioEngine?.pause()
    }

    func stop() {
        loadTask?.cancel()
        if clockEngine !== audioEngine {
            clockEngine.stop()
        }
        audioEngine.stop()
        releaseIncomingAudioEngine()
        activeOverlapConfig = nil
        clearIncomingPrefetch()
    }

    private func releaseIncomingAudioEngine() {
        incomingAudioEngine?.shutdown()
        incomingAudioEngine = nil
    }

    /// Reloads arrangement and waveform metadata for the already-loaded current song.
    @MainActor
    func refreshCurrentSongState() {
        guard let song = currentSong, song.id == loadedSongID, isLoaded else { return }
        refreshWaveformSnapshots()
        applySongEngineState(for: song)
    }

    func seek(to time: TimeInterval) {
        // Seeking during overlap would require timeline alignment between two
        // independent engines. For now, we cancel the overlap handoff and seek
        // only the active engine.
        guard incomingAudioEngine == nil else {
            audioEngine.cancelScheduledOverlapStart()
            releaseIncomingAudioEngine()
            activeOverlapConfig = nil
            clearIncomingPrefetch()
            clockEngine.seek(to: time)
            audioEngine.seek(to: time)
            return
        }

        if clockEngine !== audioEngine {
            clockEngine.seek(to: time)
        }
        audioEngine.seek(to: time)
    }

    func scheduleSectionTransition(to markerStart: TimeInterval, at transitionTime: TimeInterval) {
        guard isLoaded else { return }
        audioEngine.scheduleTransition(to: markerStart, at: transitionTime)
        if clockEngine !== audioEngine {
            clockEngine.scheduleTransition(to: markerStart, at: transitionTime)
        }
    }

    func cancelScheduledSectionTransition() {
        audioEngine.cancelScheduledTransition()
        if clockEngine !== audioEngine {
            clockEngine.cancelScheduledTransition()
        }
    }

    func snapToScheduledSection(_ markerStart: TimeInterval) {
        audioEngine.snapToTransitionTarget(markerStart)
        if clockEngine !== audioEngine {
            clockEngine.snapToTransitionTarget(markerStart)
        }
    }

    func goToNextSong(autoPlay: Bool = false) {
        guard currentIndex < songs.count - 1 else { return }
        currentIndex += 1
        reloadAndMaybePlay(autoPlay: autoPlay)
    }

    func goToPreviousSong(autoPlay: Bool = false) {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        reloadAndMaybePlay(autoPlay: autoPlay)
    }

    func goToSong(at index: Int, autoPlay: Bool = false) {
        guard songs.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        reloadAndMaybePlay(autoPlay: autoPlay)
    }

    private func advanceToNextSong(autoPlay: Bool) {
        guard currentIndex < songs.count - 1 else { return }
        currentIndex += 1
        reloadAndMaybePlay(autoPlay: autoPlay)
    }

    private func reloadAndMaybePlay(autoPlay: Bool) {
        audioEngine.cancelScheduledOverlapStart()
        audioEngine.cancelOverlapPlayback()
        clearIncomingPrefetch()
        activeOverlapConfig = nil
        audioEngine.cancelScheduledTransition()
        audioEngine.stop()
        clockEngine.stop()
        releaseIncomingAudioEngine()

        // After an overlap handoff the audible engine may be a disposable instance
        // while the shared clock engine still holds a stale graph. Consolidate back
        // onto the shared engine before loading the next song.
        if audioEngine !== clockEngine {
            audioEngine.shutdown()
            audioEngine = clockEngine
            bindPlaybackHandlers()
        }

        audioEngine.suspendHardware()
        loadCurrentSong(autoPlay: autoPlay)
    }

    func applyOutputRouting() {
        guard routingProvider != nil else { return }
        let wasPlaying = audioEngine.isPlaying
        let preservedTime = audioEngine.currentTime
        audioEngine.cancelScheduledTransition()
        audioEngine.pause()
        loadCurrentSong(autoPlay: wasPlaying, preservedTime: preservedTime)
    }

    func updateGroupMix(context: ModelContext, persist: Bool = true) {
        guard let snapshot = groupMixProvider?() else { return }
        audioEngine.applyGroupMix(snapshot)
        incomingAudioEngine?.applyGroupMix(snapshot)
        if persist {
            try? context.save()
        }
    }

    /// Live fader scrubbing: update audible mix without touching SwiftData.
    func applyProvisionalGroupVolume(groupID: UUID?, volume: Double) {
        let gain = Float(volume)
        audioEngine.applyProvisionalGroupVolume(groupID: groupID, volume: gain)
        incomingAudioEngine?.applyProvisionalGroupVolume(groupID: groupID, volume: gain)
    }

    private func applyGroupMixFromProvider() {
        guard let snapshot = groupMixProvider?() else { return }
        audioEngine.applyGroupMix(snapshot)
        incomingAudioEngine?.applyGroupMix(snapshot)
    }

    /// Keeps the shared UI clock engine timeline aligned with the currently loaded song.
    /// The audible playback engine may differ during overlap crossfades, so we must
    /// retarget the clock used by section cue UI to the same song duration/tempo.
    private func syncClockEngine(for song: Song, preservedTime: TimeInterval?) {
        let isClockMuted = clockEngine !== audioEngine
        let layout = songEngineLayout(for: song)
        let targetDuration = audioEngine.duration
        let targetTime = preservedTime ?? 0

        clockEngine.setMasterVolume(isClockMuted ? 0 : 1)
        clockEngine.setSuppressAutoStopOnPlaybackFinished(isClockMuted)
        clockEngine.setTempoMap(
            layout.tempoChanges,
            referenceBPM: layout.tempoChanges.referenceBPM,
            timeSignatureChanges: layout.timeSignatureChanges
        )
        clockEngine.retargetTimeline(duration: targetDuration, at: targetTime)
    }

    @MainActor
    private func performLoadCurrentSong(autoPlay: Bool, preservedTime: TimeInterval?) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoadingSong = true
        defer {
            if generation == loadGeneration {
                isLoadingSong = false
                loadTask = nil
            }
        }

        guard let song = currentSong else {
            isLoaded = false
            loadedSongID = nil
            currentWaveformSnapshot = nil
            loadError = nil
            return
        }

        if song.id != loadedSongID {
            isLoaded = false
            currentWaveformSnapshot = nil
        }

        audioEngine.stop()
        clockEngine.stop()
        releaseIncomingAudioEngine()
        audioEngine.suspendHardware()
        if clockEngine !== audioEngine {
            clockEngine.suspendHardware()
        }

        // `Song` is a SwiftData model; never hop off this context's actor with it.
        // Streaming payloads only open files / read headers, so this is cheap on-actor.
        let preparationResult: Result<[AudioEngineManager.PreparedTrackPayload], Error> = {
            do {
                return .success(try SongTrackLoader.playbackPayloads(for: song))
            } catch {
                return .failure(error)
            }
        }()

        guard generation == loadGeneration, !Task.isCancelled else { return }

        switch preparationResult {
        case .success(let prepared):
            do {
                var payloads = prepared
                try appendTimecodePayloadIfNeeded(
                    to: &payloads,
                    song: song,
                    songIndex: currentIndex
                )
                guard generation == loadGeneration, !Task.isCancelled else { return }

                let routing = routingProvider?()
                try audioEngine.loadPreparedTracks(payloads, routing: routing)
                guard generation == loadGeneration, !Task.isCancelled else { return }

                applySongEngineState(for: song)
                applyGroupMixFromProvider()
                if let snapshot = Self.makeWaveformSnapshot(for: song) {
                    _ = storeWaveformSnapshot(snapshot, warmingPeaksIfNeeded: true)
                } else {
                    currentWaveformSnapshot = nil
                }
                loadedSongID = song.id
                isLoaded = true
                loadError = nil

                if let preservedTime {
                    audioEngine.seek(to: preservedTime)
                }

                // Keep the shared UI clock timeline aligned with this song.
                syncClockEngine(for: song, preservedTime: preservedTime)
                if autoPlay {
                    audioEngine.play()
                    if clockEngine !== audioEngine {
                        clockEngine.play()
                    }
                }
                configureOverlapSchedulingIfNeeded()
            } catch {
                loadedSongID = nil
                currentWaveformSnapshot = nil
                isLoaded = false
                loadError = error.localizedDescription
            }

        case .failure(let error):
            if error is CancellationError {
                loadError = nil
            } else {
                loadedSongID = nil
                currentWaveformSnapshot = nil
                isLoaded = false
                loadError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func refreshWaveformSnapshots() {
        guard let song = currentSong else {
            currentWaveformSnapshot = nil
            return
        }
        if let cached = waveformSnapshotsBySongID[song.id] {
            let resolved = attachingCachedPeaks(to: cached)
            currentWaveformSnapshot = resolved
            waveformSnapshotsBySongID[song.id] = resolved
            return
        }
        guard let snapshot = Self.makeWaveformSnapshot(for: song) else {
            currentWaveformSnapshot = nil
            return
        }
        _ = storeWaveformSnapshot(snapshot, warmingPeaksIfNeeded: true)
    }

    private struct SongEngineLayout {
        let sectionsByTrack: [UUID: [ArrangementDisplaySection]]
        let masterSections: [ArrangementDisplaySection]
        let removedClips: [ArrangementRemovedClip]
        let tempoChanges: [TempoChange]
        let timeSignatureChanges: [TimeSignatureChange]
        let midiEvents: [MIDIScheduler.ScheduledEvent]
    }

    private func songEngineLayout(for song: Song) -> SongEngineLayout {
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        let arrangement = projectState.arrangement
        let inputs = Self.arrangementLayoutInputs(for: song, markers: projectState.markers)
        let layout = SongArrangementStore.playbackLayoutSnapshot(
            slots: arrangement.slots,
            clipTrims: arrangement.clipTrims,
            removedClips: arrangement.removedClips,
            clipGaps: arrangement.clipGaps,
            clipRegions: arrangement.clipRegions,
            tracks: SongPlaybackArrangementLoader.playbackTracks(for: song),
            inputs: inputs
        )

        let resolvedMIDI = MIDIScheduler.scheduledEvents(
            events: projectState.midiEvents,
            tracks: song.sortedMIDITracks
        )

        return SongEngineLayout(
            sectionsByTrack: layout.trackSections,
            masterSections: layout.rulerSections,
            removedClips: arrangement.removedClips,
            tempoChanges: projectState.tempoChanges,
            timeSignatureChanges: projectState.timeSignatureChanges,
            midiEvents: resolvedMIDI
        )
    }

    private func applySongEngineState(for song: Song) {
        let layout = songEngineLayout(for: song)

        audioEngine.setArrangement(
            sectionsByTrack: layout.sectionsByTrack,
            masterSections: layout.masterSections,
            removedClips: layout.removedClips
        )

        audioEngine.setTempoMap(
            layout.tempoChanges,
            referenceBPM: layout.tempoChanges.referenceBPM,
            timeSignatureChanges: layout.timeSignatureChanges
        )
        audioEngine.configureMIDI(events: layout.midiEvents)
    }

    static func makeWaveformSnapshot(for song: Song) -> LiveSongWaveformSnapshot? {
        guard !song.sortedTracks.isEmpty else { return nil }

        let trackSources: [(url: URL, duration: TimeInterval)]
        if SongBakeStore.hasValidBake(for: song),
           let manifest = SongBakeStore.manifest(for: song) {
            trackSources = manifest.groupStems.compactMap { stem in
                guard let url = SongBakeStore.bakedStemURL(for: song, relativePath: stem.relativePath) else {
                    return nil
                }
                return (url, stem.duration)
            }
        } else {
            trackSources = song.sortedTracks.compactMap { track in
                guard let url = FileStore.trackURL(for: song, track: track),
                      let duration = FileStore.fileDuration(at: url) else { return nil }
                return (url, duration)
            }
        }
        guard !trackSources.isEmpty else { return nil }

        let fileDuration = trackSources.map(\.duration).max() ?? 0
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        let arrangement = projectState.arrangement
        let inputs = arrangementLayoutInputs(for: song, markers: projectState.markers)
        let playbackLayout = SongArrangementStore.playbackLayoutSnapshot(
            slots: arrangement.slots,
            clipTrims: arrangement.clipTrims,
            removedClips: arrangement.removedClips,
            clipGaps: arrangement.clipGaps,
            clipRegions: arrangement.clipRegions,
            tracks: SongPlaybackArrangementLoader.playbackTracks(for: song),
            inputs: inputs
        )
        let peakSections = waveformPeakSections(
            playbackLayout: playbackLayout,
            rulerSections: playbackLayout.rulerSections
        )
        let timelineDuration = SongArrangementStore.effectiveTimelineDuration(
            rulerSections: playbackLayout.rulerSections,
            trackSections: playbackLayout.trackSections
        )

        return LiveSongWaveformSnapshot(
            songID: song.id,
            songName: song.name,
            trackSources: trackSources,
            fileDuration: fileDuration,
            timelineDuration: timelineDuration,
            sections: playbackLayout.rulerSections,
            peakSections: peakSections,
            loopSlotIDs: arrangement.loopSlotIDs,
            tempoChanges: projectState.tempoChanges,
            timeSignatureChanges: projectState.timeSignatureChanges,
            // Synthetic 120 BPM markers are always injected for timing math; only
            // show measure ticks when the song actually has a set/imported tempo.
            showsMeasureGrid: song.bpm != nil
        )
    }

    /// Uses playback clip regions for peak mapping.
    static func waveformPeakSections(
        playbackLayout: ArrangementLayoutSnapshot,
        rulerSections: [ArrangementDisplaySection]
    ) -> [ArrangementDisplaySection] {
        playbackLayout.trackSections.values
            .first(where: { !$0.isEmpty })
            ?? rulerSections
    }

    private static func trackSourceDuration(for trackID: UUID, in song: Song) -> TimeInterval {
        guard let track = song.sortedTracks.first(where: { $0.id == trackID }),
              let url = FileStore.trackURL(for: song, track: track) else { return 1 }
        return FileStore.fileDuration(at: url) ?? 1
    }

    static func arrangementLayoutInputs(
        for song: Song,
        markers: [ArrangementMarker]
    ) -> ArrangementLayoutInputs {
        SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: song.sortedTracks.map(\.id),
            sourceDurationForTrack: { trackSourceDuration(for: $0, in: song) }
        )
    }

    private func configureOverlapSchedulingIfNeeded() {
        audioEngine.cancelScheduledOverlapStart()
        clearIncomingPrefetch()
        activeOverlapConfig = nil

        guard transitionAfterCurrentSong == .overlap,
              let config = overlapConfigAfterCurrentSong,
              config.isValid,
              let incoming = nextSong,
              currentSong != nil else {
            return
        }

        activeOverlapConfig = config
        prefetchIncomingSong(incoming)

        let triggerTime = max(0, audioEngine.duration - config.startOffsetSeconds)
        audioEngine.configureScheduledOverlapStart(at: triggerTime) { [weak self] in
            Task { @MainActor in
                self?.startOverlapPlaybackIfReady()
            }
        }
    }

    private func prefetchIncomingSong(_ incoming: Song) {
        incomingPrefetchTask?.cancel()
        prefetchedIncomingPayloads = nil
        prefetchedIncomingLayout = nil
        prefetchedIncomingSongID = incoming.id

        let layout = songEngineLayout(for: incoming)
        prefetchedIncomingLayout = layout

        incomingPrefetchTask = Task { @MainActor in
            let result: Result<[AudioEngineManager.PreparedTrackPayload], Error> = {
                do {
                    return .success(try SongTrackLoader.playbackPayloads(for: incoming))
                } catch {
                    return .failure(error)
                }
            }()

            guard !Task.isCancelled, prefetchedIncomingSongID == incoming.id else { return }
            if case .success(let payloads) = result {
                var mutablePayloads = payloads
                let incomingIndex = currentIndex + 1
                try? appendTimecodePayloadIfNeeded(
                    to: &mutablePayloads,
                    song: incoming,
                    songIndex: incomingIndex
                )
                prefetchedIncomingPayloads = mutablePayloads
            }
        }
    }

    private func appendTimecodePayloadIfNeeded(
        to payloads: inout [AudioEngineManager.PreparedTrackPayload],
        song: Song,
        songIndex: Int
    ) throws {
        let settings = timecodeSettingsProvider?() ?? .default
        guard settings.isEnabled else { return }

        let duration = waveformSnapshotsBySongID[song.id]?.timelineDuration
            ?? TimecodePlaybackSupport.timelineDuration(for: song)
        let priorDurations = priorSongDurations(upTo: songIndex)
        let groupID = timecodeGroupIDProvider?()

        try TimecodePlaybackSupport.appendPayloadIfNeeded(
            to: &payloads,
            settings: settings,
            songIndex: songIndex,
            priorSongDurations: priorDurations,
            duration: duration,
            groupID: groupID
        )
    }

    private func priorSongDurations(upTo songIndex: Int) -> [TimeInterval] {
        guard songIndex > 0 else { return [] }
        return songs.prefix(songIndex).map { song in
            waveformSnapshotsBySongID[song.id]?.timelineDuration
                ?? TimecodePlaybackSupport.timelineDuration(for: song)
        }
    }

    private func startOverlapPlaybackIfReady() {
        guard transitionAfterCurrentSong == .overlap,
              let incoming = nextSong,
              prefetchedIncomingSongID == incoming.id,
              let payloads = prefetchedIncomingPayloads,
              let layout = prefetchedIncomingLayout else {
            return
        }

        do {
            // Prepare/play the incoming song on a second audio engine so the audible
            // handoff doesn't require promoting track graphs inside a single engine.
            let engine: AudioEngineManager
            if let existing = incomingAudioEngine {
                engine = existing
            } else {
                engine = AudioEngineManager()
                incomingAudioEngine = engine
            }

            let routing = routingProvider?()

            try engine.loadPreparedTracks(payloads, routing: routing)
            engine.setArrangement(
                sectionsByTrack: layout.sectionsByTrack,
                masterSections: layout.masterSections,
                removedClips: layout.removedClips
            )
            engine.setTempoMap(
                layout.tempoChanges,
                referenceBPM: layout.tempoChanges.referenceBPM,
                timeSignatureChanges: layout.timeSignatureChanges
            )
            engine.configureMIDI(events: layout.midiEvents)

            if let snapshot = groupMixProvider?() {
                engine.applyGroupMix(snapshot)
            }

            // Fade in the incoming engine during the overlap window.
            // Outgoing stays alive but we suppress auto-stop at its end boundary.
            engine.setMasterVolume(0)
            engine.setSuppressAutoStopOnPlaybackFinished(true)
            engine.seek(to: 0)

            audioEngine.setSuppressAutoStopOnPlaybackFinished(true)
            audioEngine.setMasterVolume(1)

            if !engine.isPlaying {
                engine.play()
            }

            let fadeSeconds = min(0.02, activeOverlapConfig?.startOffsetSeconds ?? 0.02)
            rampEngineMasterVolume(
                engine: engine,
                from: 0,
                to: 1,
                duration: fadeSeconds
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func completeActiveOverlapTransition(to incoming: Song) {
        audioEngine.cancelScheduledOverlapStart()
        clearIncomingPrefetch()
        let startOffsetSeconds = activeOverlapConfig?.startOffsetSeconds
        activeOverlapConfig = nil

        let outgoingEngine = audioEngine
        guard let incomingEngine = incomingAudioEngine else {
            // Fallback: if the second engine wasn't created for some reason.
            currentIndex += 1
            loadedSongID = incoming.id
            isLoaded = true
            loadError = nil
            if let snapshot = Self.makeWaveformSnapshot(for: incoming) {
                _ = storeWaveformSnapshot(snapshot, warmingPeaksIfNeeded: true)
            } else {
                currentWaveformSnapshot = nil
            }
            configureOverlapSchedulingIfNeeded()
            return
        }

        // Crossfade boundary: fade outgoing engine down, then stop it.
        let fadeSeconds = min(0.02, startOffsetSeconds ?? 0.02)
        rampEngineMasterVolume(
            engine: outgoingEngine,
            from: 1,
            to: 0,
            duration: fadeSeconds
        )
        // Only stop the outgoing engine if it's not also the UI clock engine.
        // Stopping the clock engine would pause the playback cursor.
        if outgoingEngine !== clockEngine {
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeSeconds) {
                outgoingEngine.stop()
            }
        }

        // Keep the clock engine (UI playhead) running by retargeting its
        // transport to the incoming song timing. We do this even though the
        // outgoing engine may no longer be audible.
        do {
            let layout = songEngineLayout(for: incoming)
            let incomingDuration = Self.incomingTimelineDuration(for: incoming, layout: layout)

            clockEngine.setSuppressAutoStopOnPlaybackFinished(true)
            clockEngine.retargetTimeline(
                duration: incomingDuration,
                at: min(incomingEngine.currentTime, incomingDuration)
            )
            clockEngine.setTempoMap(
                layout.tempoChanges,
                referenceBPM: layout.tempoChanges.referenceBPM,
                timeSignatureChanges: layout.timeSignatureChanges
            )
            clockEngine.setMasterVolume(0)
        }

        // Promote: the incoming engine becomes the active engine.
        audioEngine = incomingEngine
        incomingAudioEngine = nil
        audioEngine.setMasterVolume(1)
        audioEngine.setSuppressAutoStopOnPlaybackFinished(false)
        bindPlaybackHandlers()

        currentIndex += 1
        loadedSongID = incoming.id
        isLoaded = true
        loadError = nil
        if let snapshot = Self.makeWaveformSnapshot(for: incoming) {
            _ = storeWaveformSnapshot(snapshot, warmingPeaksIfNeeded: true)
        } else {
            currentWaveformSnapshot = nil
        }
        configureOverlapSchedulingIfNeeded()
    }

    private func rampEngineMasterVolume(
        engine: AudioEngineManager,
        from: Float,
        to target: Float,
        duration: TimeInterval
    ) {
        engine.setMasterVolume(from)
        guard duration > 0.0001 else {
            engine.setMasterVolume(target)
            return
        }

        let stepInterval: TimeInterval = 0.005
        let steps = max(1, Int((duration / stepInterval).rounded(.up)))
        for i in 0...steps {
            let t = TimeInterval(i) / TimeInterval(steps)
            let value = from + (target - from) * Float(t)
            DispatchQueue.main.asyncAfter(deadline: .now() + (duration * t)) {
                engine.setMasterVolume(value)
            }
        }
    }

    private func clearIncomingPrefetch() {
        incomingPrefetchTask?.cancel()
        incomingPrefetchTask = nil
        prefetchedIncomingPayloads = nil
        prefetchedIncomingLayout = nil
        prefetchedIncomingSongID = nil
    }

    private static func incomingTimelineDuration(
        for song: Song,
        layout: SongEngineLayout
    ) -> TimeInterval {
        SongArrangementStore.effectiveTimelineDuration(
            rulerSections: layout.masterSections,
            trackSections: layout.sectionsByTrack
        )
    }
}

enum PlaybackCoordinatorError: LocalizedError {
    case noTracks

    var errorDescription: String? {
        switch self {
        case .noTracks:
            return "This song has no imported tracks."
        }
    }
}
