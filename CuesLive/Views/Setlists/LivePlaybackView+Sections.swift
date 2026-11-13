import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension LivePlaybackView {
    func prepareSectionAnnouncements() {
        guard coordinator.currentSong?.smartGuideEnabled == true else { return }
        sectionAnnouncer.prepare(names: loopSections.map(\.name))
    }

    func toggleSectionLoop() {
        if sectionLoop.isLooping {
            sectionLoop.endLoop()
            return
        }

        guard let section = loopSections.section(atTimeline: coordinator.currentTime) else { return }
        clearMarkerCue()
        sectionLoop.beginManualLoop(sectionID: section.id)
    }

    func handleMappedLiveAction(_ action: MappableLiveAction) {
        switch action {
        case .stop:
            stopPlayback()
        case .playPause:
            if coordinator.isPlaying {
                coordinator.pause()
            } else {
                coordinator.play()
            }
        case .fade:
            toggleGroupMixFade()
        case .loop:
            toggleSectionLoop()
        case .goToSong(let index):
            coordinator.goToSong(at: index, autoPlay: coordinator.isAudiblePlaying)
        case .goToSection(let songIndex, let sectionIndex):
            performMappedSection(songIndex: songIndex, sectionIndex: sectionIndex)
        }
    }

    private func performMappedSection(songIndex: Int, sectionIndex: Int) {
        guard coordinator.songs.indices.contains(songIndex) else { return }
        let song = coordinator.songs[songIndex]
        guard let snapshot = coordinator.resolveWaveformSnapshot(for: song),
              snapshot.sections.indices.contains(sectionIndex) else { return }
        selectSection(songIndex: songIndex, section: snapshot.sections[sectionIndex])
    }

    /// Cues a section of the current song, or switches to another song starting at the section.
    func selectSection(songIndex: Int, section: SongSection) {
        if songIndex == coordinator.currentIndex {
            cueSection(section)
            return
        }
        clearMarkerCue()
        sectionLoop.endLoopIfActive()
        coordinator.goToSong(
            at: songIndex,
            autoPlay: coordinator.isAudiblePlaying,
            startTime: section.timelineStartSeconds
        )
    }

    var loopSectionIDs: Set<UUID> {
        coordinator.currentWaveformSnapshot?.loopSectionIDs ?? []
    }

    var loopSections: [SongSection] {
        coordinator.currentWaveformSnapshot?.sections ?? []
    }

    var sectionAnnouncementTaskID: String {
        let songID = coordinator.currentSong?.id.uuidString ?? "none"
        let enabled = coordinator.currentSong?.smartGuideEnabled == true
        let names = loopSections.map(\.name).joined(separator: "|")
        return "\(songID)-\(enabled)-\(names)"
    }

    func clearMarkerCue(cancellingScheduledTransition: Bool = true) {
        if cancellingScheduledTransition, cuedSectionID != nil {
            coordinator.cancelScheduledSectionTransition()
        }
        cuedSectionID = nil
        cueFireTime = nil
        cueFlashPhase = false
    }

    func cueSection(_ section: SongSection) {
        sectionLoop.endLoopIfActive()

        if !coordinator.isPlaying {
            clearMarkerCue()
            coordinator.seek(to: section.timelineStartSeconds)
            return
        }

        if cuedSectionID == section.id {
            clearMarkerCue()
            return
        }

        cuedSectionID = section.id
        let fireTime = sectionCueFireTime(for: section)
        cueFireTime = fireTime

        guard coordinator.isLoaded else { return }
        coordinator.scheduleSectionTransition(
            to: section.timelineStartSeconds,
            at: fireTime
        )
    }

    private func sectionCueFireTime(for cuedSection: SongSection) -> TimeInterval {
        let sections = loopSections

        if let currentSection = sections.section(atTimeline: coordinator.currentTime) {
            return currentSection.timelineEndSeconds
        }

        return sections
            .map(\.timelineEndSeconds)
            .first(where: { $0 > coordinator.currentTime })
            ?? cuedSection.timelineEndSeconds
    }

    func fireMarkerCue() {
        guard let cueFireTime, let cuedSectionID else { return }
        guard coordinator.currentTime >= cueFireTime || !coordinator.hasPendingSectionTransition else { return }
        guard let section = coordinator.currentWaveformSnapshot?.sections.first(where: { $0.id == cuedSectionID }) else {
            clearMarkerCue(cancellingScheduledTransition: false)
            return
        }
        coordinator.snapToScheduledSection(section.timelineStartSeconds)
        clearMarkerCue(cancellingScheduledTransition: false)
    }
}
