import AVFoundation
import Foundation
import Observation
import os

@Observable
final class AudioEngineManager {
    static let shared = AudioEngineManager()

    struct TrackSettings: Equatable {
        var volume: Float
        var pan: Float = 0
        var isMuted: Bool
        var isSolo: Bool
        var trimStart: TimeInterval
        var trimEnd: TimeInterval?
        var ignoresSolo: Bool = false
        /// Generated stems (e.g. click) that follow the master timeline 1:1.
        var bypassesArrangementMapping: Bool = false
    }

    struct PreparedTrackPayload: Sendable {
        let id: UUID
        let buffer: any StemSampleSource
        let settings: TrackSettings
        let groupID: UUID?
    }

    private struct TrackState {
        let trackID: UUID
        let memoryPlayer: TrackMemoryPlayer
        let timePitchNode: AVAudioUnitTimePitch
        var settings: TrackSettings
        let fileDuration: TimeInterval
        var groupID: UUID?
        let sourceFormat: AVAudioFormat

        var playbackOutputNode: AVAudioNode {
            timePitchNode
        }
    }

    private let engine = AVAudioEngine()
    private let masterMixer = AVAudioMixerNode()
    private let announcementSource = AnnouncementSource()
    private var isAnnouncementPlayerWired = false
    private let transport = AudioPlaybackTransport()
    private let midiScheduler: MIDIScheduler
    private var tracks: [UUID: TrackState] = [:]
    private var overlapTracks: [UUID: TrackState] = [:]
    private(set) var isOverlapPlaybackActive = false
    private var overlapStartMasterTime: TimeInterval = 0
    private var scheduledOverlapStartTime: TimeInterval?
    private var overlapStartHandler: (() -> Void)?
    private var didNotifyPlaybackFinished = false
    private var suppressAutoStopOnPlaybackFinished = false
    private var playbackTimer: Timer?
    /// Nil until the song's timeline is applied; tracks then play their trimmed files linearly.
    private var playbackLayout: SongPlaybackLayout?
    private var routingSnapshot: OutputRoutingSnapshot?
    private var groupMixSnapshot = GroupMixSnapshot.default
    private var tempoChanges: [TempoChange] = []
    private var referenceBPM: Double = 0
    private var timeSignatureChanges: [TimeSignatureChange] = []
    private var lastAppliedPitchCompensationCents: Float?

    private static let outputLogger = Logger(subsystem: "live.cues", category: "AudioOutput")
    private static let outputProbeQueue = DispatchQueue(label: "live.cues.output-probe", qos: .utility)
    private static let outputProbeUnresponsiveAfter: TimeInterval = 6

    @ObservationIgnored private var configurationChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var outputRecoveryTimer: Timer?
    @ObservationIgnored private var outputProbeWatchdog: Timer?
    @ObservationIgnored private var failedOutputRecoveryAttempts = 0
    @ObservationIgnored private var outputRecoveryGeneration = 0
    /// Set by `suspendHardware()`: the engine is stopped on purpose, not lost.
    @ObservationIgnored private var isHardwareSuspended = false

    private(set) var groupMeterLevels: [UUID: Float] = [:]
    private(set) var trackMeterLevels: [UUID: Float] = [:]

    var referenceSampleRate: Double {
        DecodedStemBuffer.engineSampleRate
    }

    private(set) var isPlaying = false
    /// True while the output device is gone and the graph has not been rebuilt yet.
    /// Playback is held paused meanwhile.
    private(set) var isOutputLost = false
    /// True when a device probe has gone unanswered for a while: the device is listed
    /// but CoreAudio cannot start it, so waiting will not fix it.
    private(set) var isOutputUnresponsive = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var onPlaybackFinished: (() -> Void)?
    /// Called when playback reaches the end of the timeline while still playing.
    /// Return `true` to keep playing (for example after a section-loop wrap); `false` to finish normally.
    var onWillReachEnd: (() -> Bool)?

    init() {
        midiScheduler = MIDIScheduler(transport: transport)
        engine.attach(masterMixer)
        engine.connect(masterMixer, to: engine.mainMixerNode, format: nil)
        wireAnnouncementPlayerIfNeeded()
        #if os(iOS)
        configureAudioSession()
        #endif
        applyStableMaximumFramesToRender()
        observeEngineConfigurationChanges()
    }

    /// Duration of one measure ending at `timelineSeconds`, using the active tempo/meter.
    func measureLeadDuration(endingAt timelineSeconds: TimeInterval) -> TimeInterval {
        let tempos = tempoChanges.isEmpty
            ? [TempoChange(startMeasure: 1, bpm: referenceBPM > 0 ? referenceBPM : TempoChange.defaultBPM)]
            : tempoChanges
        return MeasureTiming.measureLeadDuration(
            endingAt: timelineSeconds,
            tempoChanges: tempos,
            timeSignatureChanges: timeSignatureChanges
        )
    }

    /// Speaks a Smart Guide callout. It follows the Cues group's output routing and fader.
    func playAnnouncement(_ stem: DecodedStemBuffer) {
        guard !isOutputLost, let announcementSource else { return }
        wireAnnouncementPlayerIfNeeded()
        try? startEngineIfNeeded()
        applyAnnouncementGain()
        announcementSource.play(stem)
    }

    private func wireAnnouncementPlayerIfNeeded() {
        guard !isAnnouncementPlayerWired, let announcementSource else { return }
        if announcementSource.sourceNode.engine == nil {
            engine.attach(announcementSource.sourceNode)
        }
        engine.disconnectNodeOutput(announcementSource.sourceNode)
        OutputRoutingManager.clearChannelMap(on: announcementSource.sourceNode)
        engine.connect(announcementSource.sourceNode, to: masterMixer, format: announcementSource.format)
        isAnnouncementPlayerWired = true
    }

    /// Smart Guide shares the Cues group's fader and mute with the Cues track group.
    private func applyAnnouncementGain() {
        guard let announcementSource else { return }
        let snapshot = groupMixSnapshot
        guard let guideGroupID = routingSnapshot?.guideGroupID else {
            announcementSource.setGain(1)
            return
        }
        let muted = snapshot.mutedGroupIDs.contains(guideGroupID)
        announcementSource.setGain(muted ? 0 : (snapshot.volumeByGroupID[guideGroupID] ?? 1))
    }

    #if os(iOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setPreferredSampleRate(DecodedStemBuffer.engineSampleRate)
        AudioOutputDeviceService.applyStableBufferSize()
        try? session.setActive(true)
    }
    #endif

    private func applyStableMaximumFramesToRender() {
        engine.outputNode.auAudioUnit.maximumFramesToRender = AudioOutputDeviceService.stableBufferFrameSize
    }

    func loadTracks(
        _ payloads: [(id: UUID, url: URL, settings: TrackSettings, groupID: UUID?)],
        routing: OutputRoutingSnapshot? = nil
    ) throws {
        let prepared = try payloads.map { payload in
            try Self.prepareTrackPayload(
                id: payload.id,
                url: payload.url,
                settings: payload.settings,
                groupID: payload.groupID
            )
        }
        try loadPreparedTracks(prepared, routing: routing)
    }

    func loadPreparedTracks(
        _ payloads: [PreparedTrackPayload],
        routing: OutputRoutingSnapshot? = nil
    ) throws {
        clearOutputLoss()
        cancelOverlapPlayback()
        stop()
        stopEngineForGraphChanges()
        teardownTracks()
        playbackLayout = nil
        routingSnapshot = routing

        var loadedTracks: [UUID: TrackState] = [:]
        do {
            for payload in payloads {
                loadedTracks[payload.id] = try buildTrackState(for: payload)
            }
            tracks = loadedTracks

            // A missing device must not fail the load; recovery waits for the output.
            do {
                if let routing {
                    try wireTrackOutputs(routing: routing)
                } else {
                    connectTracksToMasterMixer()
                    try startEngineIfNeeded()
                }
            } catch {
                Self.outputLogger.error("Engine failed to start while loading: \(error.localizedDescription, privacy: .public)")
                beginOutputRecoveryIfNeeded()
            }

            applyAllMixSettings()
            duration = calculateEffectiveDuration()
            transport.setDuration(duration)
        } catch {
            tracks = loadedTracks
            teardownTracks()
            throw error
        }
    }

    static func prepareTrackPayload(
        id: UUID,
        decodedBuffer: DecodedStemBuffer,
        settings: TrackSettings,
        groupID: UUID?
    ) throws -> PreparedTrackPayload {
        var resolvedSettings = settings
        let fileDuration = Double(decodedBuffer.frameCount) / decodedBuffer.sampleRate
        if resolvedSettings.trimEnd == nil {
            resolvedSettings.trimEnd = fileDuration
        }
        return PreparedTrackPayload(
            id: id,
            buffer: decodedBuffer,
            settings: resolvedSettings,
            groupID: groupID
        )
    }

    static func prepareTrackPayload(
        id: UUID,
        url: URL,
        settings: TrackSettings,
        groupID: UUID?
    ) throws -> PreparedTrackPayload {
        let decodedBuffer = try DecodedStemBuffer.decode(from: url)
        return try prepareTrackPayload(
            id: id,
            decodedBuffer: decodedBuffer,
            settings: settings,
            groupID: groupID
        )
    }

    private func buildTrackState(for payload: PreparedTrackPayload) throws -> TrackState {
        var settings = payload.settings
        let playbackBuffer = payload.buffer
        let fileDuration = Double(playbackBuffer.frameCount) / playbackBuffer.sampleRate
        if settings.trimEnd == nil {
            settings.trimEnd = fileDuration
        }

        let mapper = makeMapper(
            trackID: payload.id,
            settings: settings,
            fileDuration: fileDuration
        )
        let memoryPlayer = TrackMemoryPlayer(
            trackID: payload.id,
            buffer: playbackBuffer,
            transport: transport,
            mapper: mapper
        )

        let timePitchNode = AVAudioUnitTimePitch()
        timePitchNode.pitch = 0
        timePitchNode.rate = 1.0
        timePitchNode.auAudioUnit.shouldBypassEffect = true

        let format = playbackBuffer.audioFormat
        engine.attach(memoryPlayer.sourceNode)
        engine.attach(timePitchNode)
        engine.connect(memoryPlayer.sourceNode, to: timePitchNode, format: format)

        return TrackState(
            trackID: payload.id,
            memoryPlayer: memoryPlayer,
            timePitchNode: timePitchNode,
            settings: settings,
            fileDuration: fileDuration,
            groupID: payload.groupID,
            sourceFormat: format
        )
    }

    /// Binds the shared playback engine to a hardware output without changing
    /// the Mac's system-wide default device.
    func selectOutputDevice(uid: String?) {
        stopEngineForGraphChanges()
        _ = adoptOutputDevice(uid)
    }

    func setArrangement(_ layout: SongPlaybackLayout) {
        if isPlaying {
            refreshCurrentTimeFromEngine()
        }

        let preservedTime = currentTime
        playbackLayout = layout
        duration = calculateEffectiveDuration()
        transport.setDuration(duration)
        syncTransportTempoMap()
        currentTime = min(preservedTime, duration)
        transport.setPausedTimeline(currentTime)
        transport.cancelScheduledTransition()
        refreshTrackMappers()
    }

    /// Replaces the clip map the playing tracks read, without moving the playhead.
    /// A clip-gain drag uses this so the level follows the fader.
    func updateArrangementClips(_ layout: SongPlaybackLayout) {
        playbackLayout = layout
        refreshTrackMappers()
    }

    func setTempoMap(
        _ changes: [TempoChange],
        referenceBPM: Double,
        timeSignatureChanges: [TimeSignatureChange]
    ) {
        tempoChanges = changes.sortedByMeasure
        self.referenceBPM = referenceBPM
        self.timeSignatureChanges = timeSignatureChanges.sortedByMeasure
        syncTransportTempoMap()
        applyTrackPitch()
    }

    private func syncTransportTempoMap() {
        guard referenceBPM > 0, !tempoChanges.isEmpty else { return }
        transport.setTempoMap(
            changes: tempoChanges,
            referenceBPM: referenceBPM,
            timeSignatureChanges: timeSignatureChanges,
            duration: duration
        )
    }

    func play() {
        guard canPlay, !isPlaying, !isOutputLost else { return }
        do {
            try startEngineIfNeeded()
        } catch {
            beginOutputRecoveryIfNeeded()
            return
        }

        let startTime = quantizeTimelineTime(transport.pausedTimelineSeconds())
        applyTrackPitch(at: startTime)
        setStreamingReadersActive(true)
        prewarmTracks(atTimelineSeconds: startTime)
        transport.beginPlayback(from: startTime)
        advanceSilentClockIfNeeded()
        isPlaying = true
        didNotifyPlaybackFinished = false
        startTimer()
        midiScheduler.start()
        refreshCurrentTimeFromEngine()
    }

    func pause() {
        guard isPlaying else { return }
        pause(at: livePlayheadTime())
    }

    /// Pauses at an already-known playhead. Use this after the hardware has been
    /// stopped: sampling host time then falls back to the transport anchor.
    private func pause(at timeline: TimeInterval) {
        transport.pause(capturingTimeline: timeline)
        isPlaying = false
        stopTimer()
        midiScheduler.stop()
        currentTime = timeline
        setStreamingReadersActive(false)
    }

    func stop() {
        cancelScheduledOverlapStart()
        cancelOverlapPlayback()
        didNotifyPlaybackFinished = false
        transport.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
        midiScheduler.stop()
        setStreamingReadersActive(false)
    }

    /// Stops the underlying `AVAudioEngine` without clearing the loaded graph.
    /// Used when another engine (e.g. overlap preview) needs exclusive hardware access.
    func suspendHardware() {
        clearOutputLoss()
        isHardwareSuspended = true
        stopEngineForGraphChanges()
        invalidateAllPlayers()
    }

    /// Fully stops transport and tears down the graph. Use for disposable engine
    /// instances (for example overlap handoff engines) before releasing them.
    func shutdown() {
        clearOutputLoss()
        cancelScheduledOverlapStart()
        cancelOverlapPlayback()
        didNotifyPlaybackFinished = false
        transport.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
        midiScheduler.stop()
        setStreamingReadersActive(false)
        silenceMeters()
        stopEngineForGraphChanges()
        invalidateAllPlayers()
        detachAllTracks()
        routingSnapshot = nil
    }

    deinit {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
        outputRecoveryTimer?.invalidate()
        outputProbeWatchdog?.invalidate()
        stopEngineForGraphChanges()
        invalidateAllPlayers()
    }

    private func invalidateAllPlayers() {
        for track in tracks.values {
            track.memoryPlayer.invalidateRendering()
        }
        for track in overlapTracks.values {
            track.memoryPlayer.invalidateRendering()
        }
    }

    /// Restarts the audio graph after `suspendHardware()` if tracks are still loaded.
    func resumeHardware() {
        guard !tracks.isEmpty else { return }
        try? startEngineIfNeeded()
    }

    /// When true, this engine will not call `stop()` automatically when it reaches
    /// the end of its timeline. Useful for external handoffs (e.g. crossfades
    /// between two independent engines).
    func setSuppressAutoStopOnPlaybackFinished(_ suppress: Bool) {
        suppressAutoStopOnPlaybackFinished = suppress
    }

    #if DEBUG
    private var captureTapNode: AVAudioNode?

    /// Records what one track renders (before routing and the speakers) so tests can inspect
    /// the real signal path. `silenceSpeakers` mutes the hardware output without touching the tap.
    func installCaptureTapForTesting(
        trackID: UUID? = nil,
        silenceSpeakers: Bool,
        handler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        removeCaptureTapForTesting()
        // Tapping the track output keeps the capture at the stem's own sample rate.
        guard let node = (trackID.flatMap { tracks[$0] } ?? tracks.values.first)?.playbackOutputNode else { return }
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, time in
            handler(buffer, time)
        }
        captureTapNode = node
        if silenceSpeakers {
            engine.mainMixerNode.outputVolume = 0
        }
    }

    func removeCaptureTapForTesting() {
        captureTapNode?.removeTap(onBus: 0)
        captureTapNode = nil
    }
    #endif

    /// Sets a master output gain for this engine. This is used for crossfades
    /// between two engines.
    func setMasterVolume(_ volume: Float) {
        masterMixer.outputVolume = volume
        // Multi-channel routing bypasses `masterMixer`; keep main mixer in sync.
        engine.mainMixerNode.outputVolume = volume
    }

    /// Updates the transport timeline without swapping the audio graph.
    ///
    /// This is useful when another engine is providing audible output but the
    /// app needs a consistent playhead for UI (e.g. overlap crossfades).
    func retargetTimeline(duration newDuration: TimeInterval, at timelineSeconds: TimeInterval) {
        // Reset end-of-playback notification state for the new duration.
        didNotifyPlaybackFinished = false

        let clampedDuration = max(0, newDuration)
        duration = clampedDuration

        transport.setDuration(clampedDuration)

        let clampedTimeline = quantizeTimelineTime(max(0, min(timelineSeconds, clampedDuration)))
        currentTime = clampedTimeline
        transport.setPausedTimeline(clampedTimeline)

        if isPlaying, let hostTime = currentHostTime() {
            // Re-anchor so wall time continues from the right timeline instantly.
            transport.resetAnchor(to: clampedTimeline, hostTime: hostTime)
        }
    }

    func configureScheduledOverlapStart(at time: TimeInterval?, handler: (() -> Void)?) {
        scheduledOverlapStartTime = time
        overlapStartHandler = handler
    }

    func cancelScheduledOverlapStart() {
        scheduledOverlapStartTime = nil
        overlapStartHandler = nil
    }

    func beginOverlapPlayback(
        payloads: [PreparedTrackPayload],
        clipsByTrack: [UUID: [TrackClip]]?,
        atMasterTime masterTime: TimeInterval
    ) throws {
        guard !isOverlapPlaybackActive, !payloads.isEmpty else { return }

        let quantizedStart = quantizeTimelineTime(masterTime)
        overlapStartMasterTime = quantizedStart
        isOverlapPlaybackActive = true

        for payload in payloads {
            let trackState = try buildOverlapTrackState(
                for: payload,
                clips: clipsByTrack.map { $0[payload.id] ?? [] }
            )
            overlapTracks[payload.id] = trackState
            trackState.memoryPlayer.setPlaybackWindow(offset: quantizedStart, endTimeline: nil)
            connectOverlapTrackToMasterMixer(trackState)
        }

        applyOverlapMixSettings()
        for track in overlapTracks.values {
            track.memoryPlayer.sampleSource.setReaderActive(true)
        }
        prewarmOverlapTracks(atTimelineSeconds: quantizedStart)
    }

    /// Promotes overlap tracks to primary and returns the incoming song timeline position.
    @discardableResult
    func completeOverlapTransition(incomingDuration: TimeInterval) -> TimeInterval {
        guard isOverlapPlaybackActive else { return 0 }

        // This method runs at an "audible" boundary. We reset the finish-notification
        // guard so the incoming song can finish later, and we re-anchor transport
        // so the timeline stays continuous.
        didNotifyPlaybackFinished = false

        let incomingTimeline = max(0, currentTime - overlapStartMasterTime)
        cancelScheduledOverlapStart()

        // Prevent any pending timeline warps from the outgoing song from affecting the
        // incoming song immediately after promotion.
        transport.cancelScheduledTransition()

        // Stop the engine and wait for the IO thread before detaching outgoing nodes.
        let wasPlaying = isPlaying
        stopEngineForGraphChanges()
        teardownTracks(withIDs: Set(tracks.keys), stopEngine: false)

        tracks = overlapTracks
        overlapTracks = [:]
        isOverlapPlaybackActive = false
        overlapStartMasterTime = 0

        for id in tracks.keys {
            tracks[id]?.memoryPlayer.setPlaybackWindow(offset: 0, endTimeline: nil)
        }

        duration = incomingDuration
        transport.setDuration(incomingDuration)

        let clampedIncoming = quantizeTimelineTime(min(incomingTimeline, incomingDuration))
        currentTime = clampedIncoming
        if isPlaying {
            // Re-anchor the shared transport at the new song's timeline position using
            // the current render host time, so timeline mapping continues without waiting
            // for the next render callback.
            if let hostTime = currentHostTime() {
                transport.resetAnchor(to: clampedIncoming, hostTime: hostTime)
            } else {
                transport.setPausedTimeline(clampedIncoming)
                transport.beginPlayback(from: clampedIncoming)
            }
        } else {
            transport.setPausedTimeline(clampedIncoming)
        }

        applyAllMixSettings()
        if wasPlaying {
            try? startEngineIfNeeded()
        }
        return clampedIncoming
    }

    func cancelOverlapPlayback() {
        guard isOverlapPlaybackActive || !overlapTracks.isEmpty else {
            isOverlapPlaybackActive = false
            overlapStartMasterTime = 0
            return
        }

        teardownOverlapTracks()
        isOverlapPlaybackActive = false
        overlapStartMasterTime = 0
    }

    func seek(to time: TimeInterval) {
        let clamped = quantizeTimelineTime(clampedTimelineTime(time))
        transport.cancelScheduledTransition()
        currentTime = clamped
        transport.setPausedTimeline(clamped)
        applyTrackPitch(at: clamped)
        prewarmTracks(atTimelineSeconds: clamped)
        midiScheduler.reset(toTimeline: clamped)

        if isPlaying {
            transport.beginPlayback(from: clamped)
        }
    }

    /// Configures MIDI playback for the current song with fully-resolved events.
    /// Events are sent in sync with the shared transport during playback.
    func configureMIDI(events: [MIDIScheduler.ScheduledEvent]) {
        midiScheduler.configure(events: events)
    }

    /// Restarts the engine after graph edits that require a full stop and re-anchors transport.
    private func restorePlaybackClock(at timeline: TimeInterval, afterGraphChange wasPlaying: Bool) {
        let clamped = quantizeTimelineTime(clampedTimelineTime(timeline))
        currentTime = clamped
        transport.setPausedTimeline(clamped)

        guard wasPlaying else { return }

        try? startEngineIfNeeded()
        let hostTime = currentHostTime() ?? mach_absolute_time()
        transport.resetAnchor(to: clamped, hostTime: hostTime)
        refreshCurrentTimeFromEngine()
    }

    private func prewarmTracks(atTimelineSeconds timeline: TimeInterval, trackIDs: Set<UUID>? = nil) {
        let targets = tracks.values.filter { track in
            if let trackIDs { return trackIDs.contains(track.trackID) }
            return true
        }
        guard !targets.isEmpty else { return }

        // Each StreamingStemBuffer owns its own reader queue/file, so warm them
        // in parallel (capped) instead of serially blocking the caller.
        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: 8)
        for track in targets {
            group.enter()
            gate.wait()
            DispatchQueue.global(qos: .userInitiated).async {
                track.memoryPlayer.prewarm(atTimelineSeconds: timeline)
                gate.signal()
                group.leave()
            }
        }
        group.wait()
    }

    private func setStreamingReadersActive(_ active: Bool) {
        for track in tracks.values {
            track.memoryPlayer.sampleSource.setReaderActive(active)
        }
        for track in overlapTracks.values {
            track.memoryPlayer.sampleSource.setReaderActive(active)
        }
    }

    private func prewarmOverlapTracks(atTimelineSeconds timeline: TimeInterval) {
        let targets = Array(overlapTracks.values)
        guard !targets.isEmpty else { return }

        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: 8)
        for track in targets {
            group.enter()
            gate.wait()
            DispatchQueue.global(qos: .userInitiated).async {
                track.memoryPlayer.prewarm(atTimelineSeconds: timeline)
                gate.signal()
                group.leave()
            }
        }
        group.wait()
    }

    func scheduleTransition(to targetOffset: TimeInterval, at transitionTimelineTime: TimeInterval) {
        let target = quantizeTimelineTime(clampedTimelineTime(targetOffset))
        let transitionAt = quantizeTimelineTime(clampedTimelineTime(transitionTimelineTime))

        if isPlaying {
            refreshCurrentTimeFromEngine()
        }

        currentTime = quantizeTimelineTime(currentTime)
        transport.setPausedTimeline(currentTime)

        let sampleThreshold = 1.0 / referenceSampleRate
        if transitionAt <= currentTime + sampleThreshold {
            transport.clearScheduledTransition()
            seek(to: target)
            if !isPlaying {
                play()
            }
            return
        }

        // Streaming stems only keep a window around the playhead resident. Pinning pages the
        // target in without moving that window, so the audio still playing is not evicted
        // and the section's first frames are there when the jump lands.
        transitionPinTarget = target
        transport.scheduleTransition(to: target, at: transitionAt)
        isAwaitingScheduledTransition = true
        applyLoopPrefetch()
    }

    func cancelScheduledTransition() {
        transport.cancelScheduledTransition()
        isAwaitingScheduledTransition = false
        transitionPinTarget = nil
        applyLoopPrefetch()
    }

    private var transitionPinTarget: TimeInterval?

    /// Arms a sample-accurate transport loop for the active arrangement section.
    func setSectionLoop(start: TimeInterval, end: TimeInterval) {
        transport.setLoopRegion(start: start, end: end)
        applyLoopPrefetch()
    }

    func clearSectionLoop() {
        // Fold the unwrapped loop clock onto the audible playhead, re-anchored to
        // lastRenderTime so UI reads cannot underflow against a newer audio anchor.
        guard hasActiveSectionLoop else {
            applyLoopPrefetch()
            return
        }
        let continueFrom = livePlayheadTime()
        let hostTime = currentHostTime()
        transport.clearLoopRegion(continuingFrom: continueFrom, hostTime: hostTime)
        currentTime = continueFrom
        transport.cancelScheduledTransition()
        applyTrackPitch(at: continueFrom)
        prewarmTracks(atTimelineSeconds: continueFrom)
        midiScheduler.reset(toTimeline: continueFrom)
        applyLoopPrefetch()
    }

    /// Where streaming stems must keep audio resident regardless of the playhead: the target of
    /// a jump that has not happened yet, otherwise the start of the armed loop.
    private var pinnedPrefetchTimeline: TimeInterval? {
        if let transitionPinTarget, transport.hasPendingTransition {
            return transitionPinTarget
        }
        return transport.currentLoopRegion()?.start
    }

    /// Streaming stems evict pages behind the playhead, so the audio under the
    /// loop start (or a cued section's start) has to be pinned before playback lands on it.
    /// The live view re-applies this on every playback tick, so anything that must stay
    /// pinned has to be reflected here and not only set once.
    private func applyLoopPrefetch() {
        let pinned = pinnedPrefetchTimeline
        for track in tracks.values {
            track.memoryPlayer.prepareLoopPrefetch(atMasterTimeline: pinned)
        }
        for track in overlapTracks.values {
            track.memoryPlayer.prepareLoopPrefetch(atMasterTimeline: pinned)
        }
    }

    var hasActiveSectionLoop: Bool {
        transport.hasActiveLoopRegion
    }

    /// True while a scheduled section jump has not yet been taken by the audio thread.
    var hasPendingSectionTransition: Bool {
        transport.hasPendingTransition
    }

    /// Incremented each time a scheduled section jump completes, so views can react to
    /// it even when the playhead lands before the time the jump was scheduled for.
    private(set) var scheduledTransitionCompletions = 0
    private var isAwaitingScheduledTransition = false

    /// Settles state that follows the playhead once the audio thread has taken a jump.
    private func finishScheduledTransitionIfNeeded() {
        guard isAwaitingScheduledTransition, !transport.hasPendingTransition else { return }
        isAwaitingScheduledTransition = false
        transitionPinTarget = nil
        let landed = livePlayheadTime()
        currentTime = landed
        applyTrackPitch(at: landed)
        midiScheduler.reset(toTimeline: landed)
        applyLoopPrefetch()
        scheduledTransitionCompletions += 1
    }

    /// Called when the UI observes that a scheduled jump is due. The audio thread owns the
    /// jump and re-anchors the clock itself, so this only settles dependent state; moving
    /// the clock from here would land at an arbitrary moment and glitch the audio.
    func snapToTransitionTarget(_ targetOffset: TimeInterval) {
        finishScheduledTransitionIfNeeded()
    }

    func updateTrackSettings(id: UUID, settings: TrackSettings) {
        guard var track = tracks[id] else { return }
        track.settings = settings
        tracks[id] = track
        applyTrackPitch()
        applyAllMixSettings()
        duration = calculateEffectiveDuration()
        transport.setDuration(duration)
        syncTransportTempoMap()
        refreshTrackMappers()
    }

    /// Audible-only volume/pan update for dragging a fader: skips the pitch, duration and
    /// mapper refresh that `updateTrackSettings` does.
    func applyLiveTrackMix(id: UUID, volume: Float, pan: Float) {
        guard var track = tracks[id] else { return }
        track.settings.volume = volume
        track.settings.pan = pan
        tracks[id] = track
        applyAllMixSettings()
    }

    func applyGroupMix(_ snapshot: GroupMixSnapshot) {
        groupMixSnapshot = snapshot
        applyAllMixSettings()
    }

    func updateTrackGroup(id: UUID, groupID: UUID?) {
        guard var track = tracks[id] else { return }
        track.groupID = groupID
        tracks[id] = track
    }

    /// Rewires the loaded tracks onto `routing` without replacing their players.
    func applyOutputRoutingKeepingTracks(_ routing: OutputRoutingSnapshot) {
        guard !tracks.isEmpty else {
            routingSnapshot = routing
            return
        }

        let wasPlaying = isPlaying
        let preservedTime = currentTime
        if wasPlaying {
            pause(at: preservedTime)
        }

        routingSnapshot = routing
        do {
            try wireTrackOutputs(routing: routing)
        } catch {
            routingSnapshot = nil
            connectTracksToMasterMixer()
            try? startEngineIfNeeded()
        }
        applyAllMixSettings()

        guard wasPlaying else { return }
        play()
    }

    func reapplyOutputRoutingIfNeeded() {
        guard let routingSnapshot else { return }
        applyOutputRoutingKeepingTracks(routingSnapshot)
    }

    func applyProvisionalGroupVolume(groupID: UUID?, volume: Float) {
        applyGroupMix(groupMixSnapshot.replacingVolume(groupID: groupID, volume: volume))
    }

    func refreshGroupMeters() {
        var groupLevels: [UUID: Float] = [:]
        var trackLevels: [UUID: Float] = [:]

        for track in tracks.values {
            let peak = track.memoryPlayer.consumePeakMeter()
            guard peak > 0.001 else { continue }
            trackLevels[track.trackID] = peak
            let groupKey = track.groupID ?? OutputRoutingStore.ungroupedRouteID
            groupLevels[groupKey] = max(groupLevels[groupKey] ?? 0, peak)
        }

        if trackLevels.isEmpty, groupLevels.isEmpty {
            guard !trackMeterLevels.isEmpty || !groupMeterLevels.isEmpty else { return }
            trackMeterLevels = [:]
            groupMeterLevels = [:]
            return
        }

        groupMeterLevels = groupLevels
        trackMeterLevels = trackLevels
    }

    /// True while any meter still has a level worth drawing. The UI keeps
    /// refreshing after playback stops until this is false, so the release
    /// can finish instead of freezing the last peak.
    var hasVisibleMeterLevel: Bool {
        !trackMeterLevels.isEmpty || !groupMeterLevels.isEmpty
    }

    private func silenceMeters() {
        for track in tracks.values {
            track.memoryPlayer.resetPeakMeter()
        }
        for track in overlapTracks.values {
            track.memoryPlayer.resetPeakMeter()
        }
        guard !trackMeterLevels.isEmpty || !groupMeterLevels.isEmpty else { return }
        trackMeterLevels = [:]
        groupMeterLevels = [:]
    }

    func groupMeterLevel(for groupID: UUID?) -> Float {
        let key = groupID ?? OutputRoutingStore.ungroupedRouteID
        return groupMeterLevels[key] ?? 0
    }

    func applyAllMixSettings() {
        let anySolo = tracks.values.contains { $0.settings.isSolo }
        let snapshot = groupMixSnapshot

        for id in tracks.keys {
            guard let track = tracks[id] else { continue }
            var effectiveVolume = track.settings.volume
            var isAudible = true

            if anySolo {
                if !track.settings.isSolo, !track.settings.ignoresSolo {
                    effectiveVolume = 0
                    isAudible = false
                }
            } else if track.settings.isMuted {
                effectiveVolume = 0
                isAudible = false
            }

            let groupVolume: Float
            let groupMuted: Bool
            if let groupID = track.groupID {
                groupVolume = snapshot.volumeByGroupID[groupID] ?? 1
                groupMuted = snapshot.mutedGroupIDs.contains(groupID)
            } else {
                groupVolume = snapshot.ungroupedVolume
                groupMuted = snapshot.ungroupedIsMuted
            }
            effectiveVolume *= groupMuted ? 0 : groupVolume

            track.memoryPlayer.updateMix(
                volume: effectiveVolume,
                pan: track.settings.pan,
                isAudible: isAudible
            )
        }
        applyAnnouncementGain()
    }

    private func makeMapper(
        trackID: UUID,
        settings: TrackSettings,
        fileDuration: TimeInterval
    ) -> ArrangementTimelineMapper {
        guard !settings.bypassesArrangementMapping, let playbackLayout else {
            return .linear(trimStart: settings.trimStart, trimEnd: settings.trimEnd ?? fileDuration)
        }
        return ArrangementTimelineMapper(
            clips: playbackLayout.clipsByTrack[trackID] ?? [],
            fileDuration: fileDuration
        )
    }

    private func refreshTrackMappers() {
        for id in tracks.keys {
            refreshTrackMapper(for: id)
        }
    }

    private func refreshTrackMapper(for trackID: UUID) {
        guard let track = tracks[trackID] else { return }
        let mapper = makeMapper(
            trackID: trackID,
            settings: track.settings,
            fileDuration: track.fileDuration
        )
        track.memoryPlayer.updateMapper(mapper)
        tracks[trackID] = track
        // The loop start may now resolve to a different source position.
        track.memoryPlayer.prepareLoopPrefetch(atMasterTimeline: pinnedPrefetchTimeline)
    }

    /// A song whose audio is all missing still plays its timeline silently.
    private var canPlay: Bool {
        !tracks.isEmpty || duration > 0
    }

    private func clampedTimelineTime(_ time: TimeInterval) -> TimeInterval {
        max(0, min(time, duration))
    }

    private func calculateEffectiveDuration() -> TimeInterval {
        if let playbackLayout, playbackLayout.duration > 0 {
            return playbackLayout.duration
        }

        return tracks.values.map { track in
            let end = track.settings.trimEnd ?? track.fileDuration
            return max(0, end - track.settings.trimStart)
        }.max() ?? 0
    }

    private func buildOverlapTrackState(
        for payload: PreparedTrackPayload,
        clips: [TrackClip]?
    ) throws -> TrackState {
        let built = try OverlapTrackGraphBuilder.buildTrack(
            payload: payload,
            clips: clips,
            transport: transport,
            engine: engine
        )
        return TrackState(
            trackID: built.trackID,
            memoryPlayer: built.memoryPlayer,
            timePitchNode: built.timePitchNode,
            settings: built.settings,
            fileDuration: built.fileDuration,
            groupID: built.groupID,
            sourceFormat: built.sourceFormat
        )
    }

    private func connectOverlapTrackToMasterMixer(_ track: TrackState) {
        OverlapTrackGraphBuilder.connectToMasterMixer(
            playbackOutputNode: track.playbackOutputNode,
            sourceFormat: track.sourceFormat,
            mixer: masterMixer,
            in: engine
        )
    }

    private func applyOverlapMixSettings() {
        for id in overlapTracks.keys {
            guard let track = overlapTracks[id] else { continue }
            var effectiveVolume = track.settings.volume
            var isAudible = true

            if track.settings.isMuted {
                effectiveVolume = 0
                isAudible = false
            }

            let groupVolume: Float
            let groupMuted: Bool
            if let groupID = track.groupID {
                groupVolume = groupMixSnapshot.volumeByGroupID[groupID] ?? 1
                groupMuted = groupMixSnapshot.mutedGroupIDs.contains(groupID)
            } else {
                groupVolume = groupMixSnapshot.ungroupedVolume
                groupMuted = groupMixSnapshot.ungroupedIsMuted
            }
            effectiveVolume *= groupMuted ? 0 : groupVolume

            track.memoryPlayer.updateMix(
                volume: effectiveVolume,
                pan: track.settings.pan,
                isAudible: isAudible
            )
        }
    }

    private func teardownOverlapTracks() {
        guard !overlapTracks.isEmpty else { return }
        stopEngineForGraphChanges()
        for track in overlapTracks.values {
            track.memoryPlayer.invalidateRendering()
        }
        for track in overlapTracks.values {
            OverlapTrackGraphBuilder.detachPlayerGraph(
                memoryPlayer: track.memoryPlayer,
                timePitchNode: track.timePitchNode,
                from: engine
            )
        }
        overlapTracks.removeAll()
    }

    private func teardownTracks(withIDs ids: Set<UUID>, stopEngine: Bool = true) {
        guard !ids.isEmpty else { return }
        if stopEngine {
            stopEngineForGraphChanges()
        }
        for id in ids {
            tracks[id]?.memoryPlayer.invalidateRendering()
        }
        for id in ids {
            guard let track = tracks[id] else { continue }
            engine.disconnectNodeOutput(track.memoryPlayer.sourceNode)
            engine.disconnectNodeInput(track.timePitchNode)
            engine.disconnectNodeOutput(track.timePitchNode)
            engine.detach(track.memoryPlayer.sourceNode)
            engine.detach(track.timePitchNode)
            tracks.removeValue(forKey: id)
        }
    }

    private func teardownTracks() {
        stopEngineForGraphChanges()
        invalidateAllPlayers()
        detachAllTracks()
        routingSnapshot = nil
    }

    private func detachAllTracks() {
        for track in tracks.values {
            engine.disconnectNodeOutput(track.memoryPlayer.sourceNode)
            engine.disconnectNodeInput(track.timePitchNode)
            engine.disconnectNodeOutput(track.timePitchNode)
            engine.detach(track.memoryPlayer.sourceNode)
            engine.detach(track.timePitchNode)
        }
        tracks.removeAll()
    }

    private func stopEngineForGraphChanges() {
        if engine.isRunning {
            engine.stop()
        }
        // Graph edits can invalidate player connections; rewire on next use.
        isAnnouncementPlayerWired = false
    }

    private func startEngineIfNeeded() throws {
        isHardwareSuspended = false
        applyStableMaximumFramesToRender()
        if !engine.isRunning {
            try engine.start()
        }
        if isOutputLost {
            clearOutputLoss()
        }
    }

    // MARK: - Output loss recovery

    /// `AVAudioEngine` stops itself when its output device disappears or changes format.
    private func observeEngineConfigurationChanges() {
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.beginOutputRecoveryIfNeeded()
        }
    }

    /// Pauses playback and starts rebuilding the output. Ignored when the engine is
    /// running, has nothing loaded, or was stopped on purpose.
    ///
    /// Runs on the main thread during device removal, so it must not call into CoreAudio.
    private func beginOutputRecoveryIfNeeded() {
        guard !isOutputLost, !isHardwareSuspended, !tracks.isEmpty, !engine.isRunning else { return }
        Self.outputLogger.notice("Audio output lost; holding playback")

        // Resuming is left to the performer: restarting mid-song after a gap is rarely wanted.
        if isPlaying {
            pause(at: currentTime)
        }
        isOutputLost = true
        failedOutputRecoveryAttempts = 0
        scheduleOutputRecoveryAttempt(after: OutputRecoveryBackoff.delay(beforeAttempt: 0))
    }

    private func scheduleOutputRecoveryAttempt(after delay: TimeInterval) {
        outputRecoveryTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptOutputRecovery()
        }
        RunLoop.main.add(timer, forMode: .common)
        outputRecoveryTimer = timer
    }

    private func scheduleOutputRecoveryRetry() {
        failedOutputRecoveryAttempts += 1
        scheduleOutputRecoveryAttempt(after: OutputRecoveryBackoff.delay(beforeAttempt: failedOutputRecoveryAttempts))
    }

    private func attemptOutputRecovery() {
        outputRecoveryTimer?.invalidate()
        outputRecoveryTimer = nil
        guard isOutputLost else { return }

        // Starting the real engine on a half-dead device blocks for about 10 s, and
        // rewiring against a missing device falls back to the system default output.
        // A throwaway engine on a background queue proves the bound device first; the
        // next attempt is only scheduled once the probe answers, so stalls don't pile up.
        let deviceUID = routingSnapshot?.deviceUID
        let generation = outputRecoveryGeneration
        armOutputProbeWatchdog(generation: generation)
        Self.outputProbeQueue.async { [weak self] in
            let canStart = AudioOutputDeviceService.canStartOutput(uid: deviceUID)
            DispatchQueue.main.async {
                guard let self, self.isOutputLost, self.outputRecoveryGeneration == generation else { return }
                self.disarmOutputProbeWatchdog()
                if canStart {
                    self.rebuildOutput()
                } else {
                    self.scheduleOutputRecoveryRetry()
                }
            }
        }
    }

    private func armOutputProbeWatchdog(generation: Int) {
        outputProbeWatchdog?.invalidate()
        let timer = Timer(timeInterval: Self.outputProbeUnresponsiveAfter, repeats: false) { [weak self] _ in
            guard let self, self.isOutputLost, self.outputRecoveryGeneration == generation else { return }
            Self.outputLogger.error("Audio device is not responding to a start request")
            self.isOutputUnresponsive = true
        }
        RunLoop.main.add(timer, forMode: .common)
        outputProbeWatchdog = timer
    }

    private func disarmOutputProbeWatchdog() {
        outputProbeWatchdog?.invalidate()
        outputProbeWatchdog = nil
        isOutputUnresponsive = false
    }

    private func rebuildOutput() {
        Self.outputLogger.notice("Rebuilding audio output")
        do {
            if let routing = routingSnapshot {
                try wireTrackOutputs(routing: routing)
            } else {
                stopEngineForGraphChanges()
                connectTracksToMasterMixer()
                try startEngineIfNeeded()
            }
        } catch {
            Self.outputLogger.error("Output rebuild failed: \(error.localizedDescription, privacy: .public)")
            scheduleOutputRecoveryRetry()
            return
        }

        applyAllMixSettings()
        Self.outputLogger.notice("Audio output restored")
    }

    /// Clears the lost state and any pending retry. Bumping the generation lets an
    /// in-flight probe tell that its result is stale.
    private func clearOutputLoss() {
        outputRecoveryTimer?.invalidate()
        outputRecoveryTimer = nil
        disarmOutputProbeWatchdog()
        failedOutputRecoveryAttempts = 0
        outputRecoveryGeneration += 1
        isOutputLost = false
    }

    private func wireTrackOutputs(routing: OutputRoutingSnapshot) throws {
        stopEngineForGraphChanges()
        let boundRequestedDevice = adoptOutputDevice(routing.deviceUID)
        // A stale/missing device UID must not force multi-channel maps onto whatever
        // output the engine actually opened — that leaves the graph silent.
        let channelCount = (routing.deviceUID != nil && !boundRequestedDevice)
            ? 2
            : outputChannelCount(for: routing)
        disconnectTrackOutputs()
        connectTrackOutputs(routing: routing, channelCount: channelCount)
        try startEngineIfNeeded()
    }

    private func adoptOutputDevice(_ deviceUID: String?) -> Bool {
        guard let deviceUID else { return true }
        // Bind only this engine's output unit — do not change the system default.
        let bound = AudioOutputDeviceService.bindOutputDevice(uid: deviceUID, to: engine)
        applyStableMaximumFramesToRender()
        return bound
    }

    private func disconnectTrackOutputs() {
        for track in tracks.values {
            engine.disconnectNodeOutput(track.memoryPlayer.sourceNode)
            engine.disconnectNodeOutput(track.timePitchNode)
        }
    }

    private func connectTrackOutputs(routing: OutputRoutingSnapshot, channelCount: Int) {
        restoreFullOutputGain()

        // Channel-map routing is also needed on a stereo-only (2-channel) device
        // whenever a group is pinned to a single mono channel instead of the
        // default full stereo pair — otherwise every group would always spread
        // across both channels regardless of its configured destination.
        if channelCount > 2 || routing.hasNonDefaultRouting {
            let routeTracks = tracks.values.map { track in
                (
                    // Channel maps must be applied on the source node after a
                    // multi-channel connection. TimePitch stays mono and cannot
                    // carry a device-width channel map.
                    node: track.memoryPlayer.sourceNode as AVAudioNode,
                    format: track.sourceFormat,
                    destination: OutputRoutingStore.destination(for: track.groupID, snapshot: routing)
                )
            }

            var allRoutes = routeTracks
            if !routeTracks.isEmpty, let announcementSource {
                if announcementSource.sourceNode.engine == nil {
                    engine.attach(announcementSource.sourceNode)
                }
                allRoutes.append((
                    node: announcementSource.sourceNode as AVAudioNode,
                    format: announcementSource.format,
                    destination: OutputRoutingStore.guideDestination(snapshot: routing)
                ))
            }

            if OutputRoutingManager.applyChannelMapRouting(
                engine: engine,
                tracks: allRoutes,
                outputChannelCount: max(channelCount, 2)
            ) {
                // The callout node is now routed directly with the track nodes.
                isAnnouncementPlayerWired = true
                return
            }
        }

        connectTracksToMasterMixer()
    }

    private func connectTracksToMasterMixer() {
        restoreFullOutputGain()

        engine.disconnectNodeOutput(engine.mainMixerNode)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)

        for track in tracks.values {
            connectTrackToMasterMixer(track)
        }
        isAnnouncementPlayerWired = false
        wireAnnouncementPlayerIfNeeded()
    }

    private func connectTrackToMasterMixer(_ track: TrackState) {
        engine.disconnectNodeOutput(track.memoryPlayer.sourceNode)
        engine.disconnectNodeOutput(track.timePitchNode)
        OutputRoutingManager.clearChannelMap(on: track.memoryPlayer.sourceNode)
        OutputRoutingManager.clearChannelMap(on: track.timePitchNode)
        engine.connect(track.memoryPlayer.sourceNode, to: track.timePitchNode, format: track.sourceFormat)
        engine.connect(track.timePitchNode, to: masterMixer, format: track.sourceFormat)
    }

    private func restoreFullOutputGain() {
        masterMixer.outputVolume = 1
        engine.mainMixerNode.outputVolume = 1
    }

    private func outputChannelCount(for routing: OutputRoutingSnapshot) -> Int {
        let deviceCount = AudioOutputDeviceService.channelCount(for: routing.deviceUID)
        return max(routing.channelCount, deviceCount, 2)
    }

    private func quantizeTimelineTime(_ time: TimeInterval) -> TimeInterval {
        AudioTimelineMath.quantize(time, sampleRate: referenceSampleRate)
    }

    private func startTimer() {
        stopTimer()
        // Scheduled in `.common` modes so the playhead keeps advancing while the
        // run loop is in an event-tracking mode (e.g. an open context menu or an
        // active scroll), instead of freezing while audio continues to play.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            // Catches an engine that stopped without posting a configuration change.
            if !self.engine.isRunning {
                self.beginOutputRecoveryIfNeeded()
                guard self.isPlaying else { return }
            }
            self.advanceSilentClockIfNeeded()
            self.refreshCurrentTimeFromEngine()
            self.finishScheduledTransitionIfNeeded()
            self.applyTrackPitch(at: self.currentTime)

            if !self.didNotifyPlaybackFinished,
               self.currentTime >= self.duration - (1.0 / self.referenceSampleRate) {
                // Transport-level section loops wrap before duration; never auto-stop
                // while a loop region is armed or the host requests a wrap.
                if self.transport.hasActiveLoopRegion || self.onWillReachEnd?() == true {
                    self.didNotifyPlaybackFinished = false
                    return
                }
                self.didNotifyPlaybackFinished = true
                if self.isOverlapPlaybackActive || self.suppressAutoStopOnPlaybackFinished {
                    self.onPlaybackFinished?()
                } else {
                    self.stop()
                    self.onPlaybackFinished?()
                }
                return
            }

            if let scheduledStart = self.scheduledOverlapStartTime,
               !self.isOverlapPlaybackActive,
               self.currentTime >= scheduledStart {
                self.scheduledOverlapStartTime = nil
                let handler = self.overlapStartHandler
                self.overlapStartHandler = nil
                handler?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func refreshCurrentTimeFromEngine() {
        currentTime = livePlayheadTime()
    }

    private func applyTrackPitch(at timeline: TimeInterval? = nil) {
        let compensationCents: Float
        if let timeline, referenceBPM > 0, !tempoChanges.isEmpty {
            let ratio = transport.playbackRatio(at: timeline)
            compensationCents = Float(-1200 * log2(max(ratio, 0.01)))
        } else {
            compensationCents = 0
        }

        if timeline != nil,
           let lastAppliedPitchCompensationCents,
           abs(lastAppliedPitchCompensationCents - compensationCents) < 0.01 {
            return
        }
        if timeline != nil {
            lastAppliedPitchCompensationCents = compensationCents
        } else {
            lastAppliedPitchCompensationCents = nil
        }

        for id in tracks.keys {
            guard let track = tracks[id] else { continue }
            track.timePitchNode.rate = 1.0
            track.timePitchNode.pitch = compensationCents
            track.timePitchNode.auAudioUnit.shouldBypassEffect = abs(compensationCents) < 0.5
        }
    }

    /// Host-clock playhead position for UI rendering without publishing observable updates.
    func livePlayheadTime() -> TimeInterval {
        transport.audibleTimelineSeconds(atHostTime: currentHostTime())
    }

    /// With no tracks loaded nothing renders on the audio thread, so the transport never
    /// captures its start anchor or takes scheduled jumps. Drive it from here instead.
    private func advanceSilentClockIfNeeded() {
        guard tracks.isEmpty else { return }
        _ = transport.renderTimeline(atHostTime: mach_absolute_time(), captureAnchor: true)
    }

    private func currentHostTime() -> UInt64? {
        // Same clock as `advanceSilentClockIfNeeded`; there is no render time to read.
        if tracks.isEmpty { return mach_absolute_time() }
        guard let lastRenderTime = engine.outputNode.lastRenderTime,
              lastRenderTime.isHostTimeValid else { return nil }
        return lastRenderTime.hostTime
    }
}

extension AudioEngineManager.TrackSettings {
    init(track: AudioTrack) {
        volume = Float(track.volume)
        pan = Float(track.pan)
        isMuted = track.isMuted
        isSolo = track.isSolo
        trimStart = track.trimStartSeconds
        trimEnd = track.trimEndSeconds
    }
}
