import Foundation
import Observation
import SwiftData

/// Keeps `RemoteSessionHostService` wired to the live playback surface.
/// Singleton so snapshot/state providers stay alive for the whole app session.
@MainActor
@Observable
final class RemoteHostSessionController {
    static let shared = RemoteHostSessionController()

    private let host = RemoteSessionHostService.shared
    private let settings = RemoteSessionSettingsStore.shared
    private var bridge: RemoteSessionCommandBridge!

    private var coordinator: PlaybackCoordinator?
    private var sectionLoop: SectionLoopController?
    private var groupMixFade: GroupMixFadeController?
    private var modelContext: ModelContext?
    private var setlist: Setlist?
    private var cuedSectionID: UUID?
    private var cueFireTime: TimeInterval?

    /// Eagerly refreshed on each live-UI sync so auth-time snapshot pushes never depend
    /// on reconstructing SwiftData relationships under time pressure.
    private(set) var cachedSnapshot: RemoteSessionSnapshot?
    private(set) var cachedState: RemoteSessionState?
    private(set) var isLiveUIBound = false

    private var clearMarkerCueHandler: ((Bool) -> Void)?
    private var cueSectionHandler: ((SongSection) -> Void)?
    private var fireMarkerCueHandler: (() -> Void)?
    private var stopPlaybackHandler: (() -> Void)?
    private var waveformPeakPrefetchTask: Task<Void, Never>?

    private init() {
        bridge = RemoteSessionCommandBridge { [weak self] in
            self?.makeBridgeContext()
        }
        host.onCommand = { [weak self] command in
            self?.bridge.handle(command)
        }
        host.snapshotProvider = { [weak self] in
            guard let self else { return nil }
            if let cachedSnapshot {
                return cachedSnapshot
            }
            return self.rebuildCache()?.snapshot
        }
        host.stateProvider = { [weak self] in
            // Always rebuild transport state so the 10 Hz push carries a live playhead
            // and engaged button flags (play / loop / fade), not a stale cache.
            guard let self else { return nil }
            return self.refreshStateCache()
        }
        host.isLiveUIBoundProvider = { [weak self] in
            self?.isLiveUIBound ?? false
        }
        host.onSnapshotRetryTick = { [weak self] in
            self?.notifySnapshotChanged()
        }
    }

    /// Single entry point for starting/stopping Bonjour advertising from settings / app launch.
    func syncAdvertising() {
        if settings.isHostingEnabled {
            // startAdvertising is a no-op restart when already advertising,
            // so this is safe to call from frequent live UI syncs.
            host.startAdvertising(
                pin: settings.pin,
                displayName: settings.displayName,
                instanceID: settings.instanceID
            )
        } else if host.isAdvertising {
            // Intentionally end the session when hosting is turned off.
            host.stopAdvertising()
        }
    }

    func setHostingEnabled(_ enabled: Bool) {
        if enabled {
            settings.enableHosting()
            syncAdvertising()
        } else {
            settings.disableHosting()
            host.stopAdvertising()
        }
    }

    /// Drops the current client by bouncing the listener, then resumes advertising if enabled.
    func disconnectClient() {
        host.stopAdvertising()
        syncAdvertising()
    }

    func sync(
        setlist: Setlist?,
        coordinator: PlaybackCoordinator,
        sectionLoop: SectionLoopController,
        groupMixFade: GroupMixFadeController,
        modelContext: ModelContext,
        cuedSectionID: UUID?,
        cueFireTime: TimeInterval?,
        clearMarkerCue: @escaping (Bool) -> Void,
        cueSection: @escaping (SongSection) -> Void,
        fireMarkerCue: @escaping () -> Void,
        stopPlayback: @escaping () -> Void
    ) {
        self.setlist = setlist
        self.coordinator = coordinator
        self.sectionLoop = sectionLoop
        self.groupMixFade = groupMixFade
        self.modelContext = modelContext
        self.cuedSectionID = cuedSectionID
        self.cueFireTime = cueFireTime
        clearMarkerCueHandler = clearMarkerCue
        cueSectionHandler = cueSection
        fireMarkerCueHandler = fireMarkerCue
        stopPlaybackHandler = stopPlayback
        isLiveUIBound = setlist != nil

        rebuildCache()
        syncAdvertising()
        host.retrySnapshotIfNeeded()
    }

    /// Updates cue fields without touching advertising / full session rebind.
    func updateCue(cuedSectionID: UUID?, cueFireTime: TimeInterval?) {
        self.cuedSectionID = cuedSectionID
        self.cueFireTime = cueFireTime
        notifyStateChanged()
    }

    func notifySnapshotChanged() {
        rebuildCache()
        guard host.isClientAuthenticated else { return }
        host.pushSnapshot(isInitialDelivery: !host.hasSentSnapshot)
    }

    func notifyStateChanged() {
        // Prefer a lightweight state refresh; fall back to full rebuild if needed.
        if refreshStateCache() == nil {
            _ = rebuildCache()
        }
        guard host.isClientAuthenticated else { return }
        host.pushState()
    }

    /// Fast path used by the host state push loop — updates playhead / transport flags
    /// without rebuilding the full setlist snapshot.
    @discardableResult
    private func refreshStateCache() -> RemoteSessionState? {
        guard let coordinator,
              let sectionLoop,
              let groupMixFade,
              let modelContext else {
            return cachedState
        }

        let state = RemoteSessionSnapshotBuilder.makeState(
            coordinator: coordinator,
            context: modelContext,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime
        )
        cachedState = state
        return state
    }

    @discardableResult
    private func rebuildCache() -> (snapshot: RemoteSessionSnapshot, state: RemoteSessionState)? {
        guard let setlist,
              let coordinator,
              let sectionLoop,
              let groupMixFade,
              let modelContext else {
            // Do not clear existing cache — song loads / transient sync gaps must not
            // wipe the last good setlist and trigger host disconnect logic.
            return nil
        }

        let snapshot = RemoteSessionSnapshotBuilder.makeSnapshot(
            setlist: setlist,
            coordinator: coordinator,
            context: modelContext,
            hostDisplayName: settings.displayName,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime
        )
        let state = snapshot.state
        cachedSnapshot = snapshot
        cachedState = state
        prefetchMissingWaveformPeaks(for: setlist, coordinator: coordinator)
        return (snapshot, state)
    }

    /// Loads host waveform peaks for setlist songs that are not cached yet, then
    /// rebuilds / pushes the snapshot so clients get accurate waveforms.
    private func prefetchMissingWaveformPeaks(for setlist: Setlist, coordinator: PlaybackCoordinator) {
        var seenSongIDs = Set<UUID>()
        var pendingSources: [[(url: URL, duration: TimeInterval)]] = []

        for entry in setlist.sortedEntries {
            guard let song = entry.song, seenSongIDs.insert(song.id).inserted else { continue }
            guard let snapshot = coordinator.resolveWaveformSnapshot(for: song),
                  !snapshot.trackSources.isEmpty else {
                continue
            }
            if WaveformCache.shared.cachedSummedPeaks(for: snapshot.trackSources) == nil {
                pendingSources.append(snapshot.trackSources)
            }
        }

        guard !pendingSources.isEmpty else { return }

        waveformPeakPrefetchTask?.cancel()
        waveformPeakPrefetchTask = Task { @MainActor in
            for sources in pendingSources {
                guard !Task.isCancelled else { return }
                _ = await WaveformCache.shared.summedPeaks(for: sources)
            }
            guard !Task.isCancelled else { return }
            notifySnapshotChanged()
        }
    }

    private func makeBridgeContext() -> RemoteSessionCommandBridge.HostContext? {
        guard let coordinator,
              let sectionLoop,
              let groupMixFade,
              let modelContext else {
            return nil
        }
        return RemoteSessionCommandBridge.HostContext(
            coordinator: coordinator,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            modelContext: modelContext,
            setlist: setlist,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            clearMarkerCue: { [weak self] in
                self?.clearMarkerCueHandler?(true)
            },
            cueSection: { [weak self] section in
                self?.cueSectionHandler?(section)
            },
            fireMarkerCue: { [weak self] in
                self?.fireMarkerCueHandler?()
            },
            stopPlayback: { [weak self] in
                self?.stopPlaybackHandler?()
            },
            onMixChanged: { [weak self] in
                self?.notifyStateChanged()
            },
            onSetlistChanged: { [weak self] in
                self?.notifySnapshotChanged()
            }
        )
    }
}
