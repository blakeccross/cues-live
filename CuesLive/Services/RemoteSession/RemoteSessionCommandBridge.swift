import Foundation
import SwiftData

@MainActor
final class RemoteSessionCommandBridge {
    struct HostContext {
        var coordinator: PlaybackCoordinator
        var sectionLoop: SectionLoopController
        var groupMixFade: GroupMixFadeController
        var modelContext: ModelContext
        var setlist: Setlist?
        var cuedSectionID: UUID?
        var cueFireTime: TimeInterval?
        var clearMarkerCue: () -> Void
        var cueSection: (SongSection) -> Void
        var fireMarkerCue: () -> Void
        var stopPlayback: () -> Void
        var onMixChanged: () -> Void
        var onSetlistChanged: () -> Void
    }

    private let contextProvider: () -> HostContext?

    init(contextProvider: @escaping () -> HostContext?) {
        self.contextProvider = contextProvider
    }

    func handle(_ command: RemoteSessionCommand) {
        guard let host = contextProvider() else { return }

        switch command {
        case .play:
            host.coordinator.play()
        case .pause:
            host.coordinator.pause()
        case .stop:
            host.stopPlayback()
        case .seek(let time):
            host.coordinator.seek(to: time)
        case .nextSong(let autoPlay):
            host.coordinator.goToNextSong(autoPlay: autoPlay)
        case .previousSong(let autoPlay):
            host.coordinator.goToPreviousSong(autoPlay: autoPlay)
        case .goToSong(let index, let autoPlay, let startTime):
            host.coordinator.goToSong(at: index, autoPlay: autoPlay, startTime: startTime)
        case .setGroupVolume(let groupID, let volume, let provisional):
            applyVolume(groupID: groupID, volume: volume, provisional: provisional, host: host)
        case .setGroupMuted(let groupID, let muted):
            applyMute(groupID: groupID, muted: muted, host: host)
        case .setGroupSoloed(let groupID, let soloed):
            applySolo(groupID: groupID, soloed: soloed, host: host)
        case .toggleFade:
            host.groupMixFade.toggleFade(context: host.modelContext) {
                host.coordinator.updateGroupMix(context: host.modelContext, persist: false)
            } onComplete: {
                host.coordinator.updateGroupMix(context: host.modelContext)
            }
        case .clearFade:
            host.groupMixFade.clearFade(context: host.modelContext) {
                host.coordinator.updateGroupMix(context: host.modelContext)
            }
        case .cueSection(let sectionID):
            if let section = host.coordinator.currentWaveformSnapshot?.sections.first(where: { $0.id == sectionID }) {
                host.cueSection(section)
            }
        case .cancelCue:
            host.clearMarkerCue()
        case .snapToCuedSection:
            host.fireMarkerCue()
        case .toggleSectionLoop:
            toggleSectionLoop(host: host)
        case .beginManualLoop(let sectionID):
            host.clearMarkerCue()
            host.sectionLoop.beginManualLoop(sectionID: sectionID)
        case .endLoop:
            host.sectionLoop.endLoop()
        case .removeSetlistEntries(let entryIDs):
            removeSetlistEntries(entryIDs: entryIDs, host: host)
        case .moveSetlistEntries(let entryIDs, let beforeEntryID):
            moveSetlistEntries(entryIDs: entryIDs, beforeEntryID: beforeEntryID, host: host)
        case .addSongToSetlist(let songID, let atIndex):
            addSongToSetlist(songID: songID, atIndex: atIndex, host: host)
        case .addSetlistHeader(let title, let atIndex, let timeSeconds):
            addSetlistHeader(title: title, atIndex: atIndex, timeSeconds: timeSeconds, host: host)
        }
    }

    private func addSongToSetlist(songID: UUID, atIndex: Int?, host: HostContext) {
        guard let setlist = host.setlist else { return }
        let targetID = songID
        let descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == targetID })
        guard let song = try? host.modelContext.fetch(descriptor).first else { return }
        let index = atIndex ?? setlist.sortedEntries.count
        SetlistViewModel().insertSong(song, at: index, to: setlist, context: host.modelContext)
        host.coordinator.syncSetlist(setlist)
        host.onSetlistChanged()
    }

    private func addSetlistHeader(title: String, atIndex: Int?, timeSeconds: TimeInterval?, host: HostContext) {
        guard let setlist = host.setlist else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let index = atIndex ?? setlist.sortedEntries.count
        SetlistViewModel().insertHeader(
            title: trimmed,
            timeSeconds: timeSeconds,
            at: index,
            to: setlist,
            context: host.modelContext
        )
        host.coordinator.syncSetlist(setlist)
        host.onSetlistChanged()
    }

    private func removeSetlistEntries(entryIDs: [UUID], host: HostContext) {
        guard let setlist = host.setlist else { return }
        let entries = entryIDs.compactMap { entry(withRemoteID: $0, in: setlist) }
        guard !entries.isEmpty else { return }
        SetlistViewModel().removeEntries(entries, from: setlist, context: host.modelContext)
        host.coordinator.syncSetlist(setlist)
        host.onSetlistChanged()
    }

    private func moveSetlistEntries(entryIDs: [UUID], beforeEntryID: UUID?, host: HostContext) {
        guard let setlist = host.setlist else { return }
        let entries = entryIDs.compactMap { entry(withRemoteID: $0, in: setlist) }
        guard !entries.isEmpty else { return }
        SetlistViewModel().moveEntries(
            entries,
            before: beforeEntryID.flatMap { entry(withRemoteID: $0, in: setlist) },
            in: setlist,
            context: host.modelContext
        )
        host.coordinator.syncSetlist(setlist)
        host.onSetlistChanged()
    }

    private func entry(withRemoteID entryID: UUID, in setlist: Setlist) -> SetlistEntry? {
        setlist.sortedEntries.first {
            RemoteSessionSnapshotBuilder.stableEntryID(for: $0) == entryID
        }
    }

    private func applyVolume(groupID: UUID?, volume: Double, provisional: Bool, host: HostContext) {
        if provisional {
            host.coordinator.applyProvisionalGroupVolume(groupID: groupID, volume: volume)
            return
        }

        if let groupID {
            let groups = TrackGroupStore.sortedGroups(from: host.modelContext)
            if let group = groups.first(where: { $0.id == groupID }) {
                group.volume = volume
            }
        } else {
            OutputRoutingStore.config(in: host.modelContext).ungroupedVolume = volume
        }
        host.coordinator.updateGroupMix(context: host.modelContext)
        host.onMixChanged()
    }

    private func applyMute(groupID: UUID?, muted: Bool, host: HostContext) {
        if let groupID {
            let groups = TrackGroupStore.sortedGroups(from: host.modelContext)
            if let group = groups.first(where: { $0.id == groupID }) {
                group.isMuted = muted
            }
        } else {
            OutputRoutingStore.config(in: host.modelContext).ungroupedIsMuted = muted
        }
        host.coordinator.updateGroupMix(context: host.modelContext)
        host.onMixChanged()
    }

    private func applySolo(groupID: UUID?, soloed: Bool, host: HostContext) {
        if let groupID {
            let groups = TrackGroupStore.sortedGroups(from: host.modelContext)
            if let group = groups.first(where: { $0.id == groupID }) {
                group.isSoloed = soloed
            }
        } else {
            OutputRoutingStore.config(in: host.modelContext).ungroupedIsSoloed = soloed
        }
        host.coordinator.updateGroupMix(context: host.modelContext)
        host.onMixChanged()
    }

    private func toggleSectionLoop(host: HostContext) {
        if host.sectionLoop.isLooping {
            host.sectionLoop.endLoop()
            return
        }
        let sections = host.coordinator.currentWaveformSnapshot?.sections ?? []
        let playhead = host.coordinator.isPlaying
            ? host.coordinator.livePlayheadTime()
            : host.coordinator.currentTime
        guard let section = sections.section(atTimeline: playhead)
                ?? sections.first else {
            return
        }
        host.clearMarkerCue()
        host.sectionLoop.beginManualLoop(sectionID: section.id)
    }
}
