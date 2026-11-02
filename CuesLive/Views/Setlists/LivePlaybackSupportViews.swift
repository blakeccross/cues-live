import SwiftUI

struct LivePlaybackMonitorSupport: View {
    let cuedSectionID: UUID?
    let cueFireTime: TimeInterval?
    let onFireMarkerCue: () -> Void
    let dynamicCuesEnabled: Bool
    let sections: [ArrangementDisplaySection]
    let announcer: SectionAnnouncer
    @Bindable var sectionLoop: SectionLoopController
    let loopSections: [ArrangementDisplaySection]
    let loopSlotIDs: Set<UUID>
    var playbackEngine: AudioEngineManager
    let onLoopActivated: () -> Void

    var body: some View {
        SectionCueMonitor(
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            onFire: onFireMarkerCue
        )
        SectionAnnounceMonitor(
            enabled: dynamicCuesEnabled,
            sections: sections,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            announcer: announcer
        )
        SectionLoopPlaybackSupport(
            playbackEngine: playbackEngine,
            loopController: sectionLoop,
            sections: loopSections,
            loopSlotIDs: loopSlotIDs,
            onLoopActivated: onLoopActivated
        )
    }
}

struct LiveRemoteHostSyncModifier: ViewModifier {
    let setlist: Setlist
    let librarySignature: String
    let coordinator: PlaybackCoordinator
    let sectionLoop: SectionLoopController
    let groupMixFade: GroupMixFadeController
    let cuedSectionID: UUID?
    let cueFireTime: TimeInterval?
    let remoteHostController: RemoteHostSessionController
    let isClientAuthenticated: Bool
    let sync: () -> Void

    private var setlistStructureSignature: String {
        setlist.sortedEntries.map { entry in
            let identity = entry.song?.id.uuidString ?? "header:\(entry.headerTitle ?? "")"
            return "\(entry.sortOrder)|\(identity)|\(entry.transition.rawValue)"
        }
        .joined(separator: ";")
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: sync)
            .onChange(of: setlist.id) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: setlist.entries.count) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: setlistStructureSignature) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: librarySignature) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: coordinator.currentIndex) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: coordinator.isPlaying) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: sectionLoop.activeSectionID) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: sectionLoop.manualSectionID) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: groupMixFade.isFadedOut) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: groupMixFade.isFading) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: cuedSectionID) { _, newValue in
                remoteHostController.updateCue(cuedSectionID: newValue, cueFireTime: cueFireTime)
            }
            .onChange(of: cueFireTime) { _, newValue in
                remoteHostController.updateCue(cuedSectionID: cuedSectionID, cueFireTime: newValue)
            }
            .onChange(of: isClientAuthenticated) { _, connected in
                if connected {
                    remoteHostController.notifySnapshotChanged()
                }
            }
            .overlay(alignment: .top) {
                if isClientAuthenticated {
                    Text("Remote control connected")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.accent.opacity(0.85), in: Capsule())
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Row duration and missing-file checks hit the disk, so the first lookup is cached
/// until media health changes.
final class SetlistRowMetricsCache {
    private var mediaRevision = Int.min
    private var missingBySongID: [UUID: Bool] = [:]
    private var durationBySongID: [UUID: TimeInterval] = [:]

    func hasMissingMedia(_ song: Song, revision: Int) -> Bool {
        if mediaRevision != revision {
            mediaRevision = revision
            missingBySongID.removeAll()
        }
        if let cached = missingBySongID[song.id] {
            return cached
        }
        let missing = SongMediaHealth.hasMissingMedia(song)
        missingBySongID[song.id] = missing
        return missing
    }

    func timelineDuration(for song: Song, snapshot: TimeInterval?) -> TimeInterval {
        if let snapshot {
            return snapshot
        }
        if let cached = durationBySongID[song.id] {
            return cached
        }
        let duration = TimecodePlaybackSupport.timelineDuration(for: song)
        durationBySongID[song.id] = duration
        return duration
    }
}
