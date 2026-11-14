import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditView {
    var markers: [ArrangementMarker] {
        timeline.sortedMarkers
    }

    var displaySections: [SongSection] {
        timeline.sections(songEnd: timeline.duration)
    }

    /// Start of each section marker, in timeline seconds.
    var sectionMarkerTimes: [TimeInterval] {
        displaySections.map(\.timelineStartSeconds)
    }

    var loopSectionIDs: Set<UUID> {
        Set(timeline.markers.filter(\.loops).map(\.id))
    }

    var detectSectionsModifier: DetectSectionsFlowModifier {
        DetectSectionsFlowModifier(
            showingReplaceConfirm: $showingDetectSectionsConfirm,
            error: $sectionDetectionError,
            onConfirmReplace: detectSections
        )
    }

    func clearMarkerCue(cancellingScheduledTransition: Bool = true) {
        if cancellingScheduledTransition, cuedSectionID != nil {
            viewModel.cancelScheduledSectionTransition()
        }
        cuedSectionID = nil
        cueFireTime = nil
        cueFlashPhase = false
    }

    func prepareSectionAnnouncements() {
        guard song.smartGuideEnabled else { return }
        sectionAnnouncer.prepare(names: displaySections.map(\.name))
    }

    func cueSection(_ section: SongSection) {
        // Section jumps belong to the setlist screen while this editor follows it.
        guard !viewModel.followsSetlist else { return }
        sectionLoop.endLoopIfActive()

        if !audioEngine.isPlaying {
            clearMarkerCue()
            viewModel.seekAndPlay(to: section.timelineStartSeconds)
            return
        }

        if cuedSectionID == section.id {
            clearMarkerCue()
            return
        }

        cuedSectionID = section.id
        cueFireTime = sectionCueFireTime(for: section)

        guard viewModel.isLoaded else { return }
        viewModel.scheduleSectionTransition(
            to: section.timelineStartSeconds,
            at: cueFireTime ?? section.timelineStartSeconds
        )
    }

    private func sectionCueFireTime(for cuedSection: SongSection) -> TimeInterval {
        if let currentSection = displaySections.section(atTimeline: audioEngine.currentTime) {
            return currentSection.timelineEndSeconds
        }

        if audioEngine.currentTime < cuedSection.timelineStartSeconds {
            return cuedSection.timelineStartSeconds
        }

        return displaySections
            .map(\.timelineEndSeconds)
            .first(where: { $0 > audioEngine.currentTime })
            ?? cuedSection.timelineEndSeconds
    }

    func fireMarkerCue() {
        guard let cueFireTime, let cuedSectionID else { return }
        guard audioEngine.currentTime >= cueFireTime || !audioEngine.hasPendingSectionTransition else { return }
        guard let section = displaySections.first(where: { $0.id == cuedSectionID }) else {
            clearMarkerCue(cancellingScheduledTransition: false)
            return
        }

        viewModel.snapToScheduledSection(section.timelineStartSeconds)
        clearMarkerCue(cancellingScheduledTransition: false)
    }

    func toggleLoopSection(_ section: SongSection) {
        var loops = loopSectionIDs
        sectionLoop.toggleLoop(on: section.id, loopSectionIDs: &loops)
        commitTimelineEdit("Toggle Loop") { timeline in
            for index in timeline.markers.indices {
                timeline.markers[index].loops = loops.contains(timeline.markers[index].id)
            }
        }
    }

    func addSection(at timelineTime: TimeInterval) {
        let snappedTime = MeasureTiming.snapToNearestBeat(
            max(0, timelineTime),
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let start = min(max(0, snappedTime), max(songDuration - 0.01, 0))
        guard !markers.contains(where: { abs($0.startSeconds - start) < 0.02 }) else { return }

        let newMarker = ArrangementMarker(
            name: "Section \(markers.count + 1)",
            startSeconds: start,
            sortOrder: markers.count
        )
        commitTimelineEdit("Add Section") { timeline in
            timeline.markers.append(newMarker)
        }

        if let section = displaySections.first(where: { $0.id == newMarker.id }) {
            activeSheet = .renameSection(section, title: "Name Section")
        }
    }

    func requestDetectSections() {
        guard !isDetectingSections else { return }
        if markers.count > 1 {
            showingDetectSectionsConfirm = true
        } else {
            detectSections()
        }
    }

    private func detectSections() {
        guard !isDetectingSections else { return }
        let urls = SongSectionDetector.analysisTracks(in: song)
            .compactMap { FileStore.trackURL(for: song, track: $0) }
        let duration = songDuration
        isDetectingSections = true

        Task {
            defer { isDetectingSections = false }
            do {
                let starts = try await SongSectionDetector.detectSectionStarts(from: urls)
                let detected = SongSectionDetector.markers(
                    fromSectionStarts: starts,
                    songDuration: duration
                )
                guard detected.count > 1 else { throw SongSectionDetectorError.noSectionsFound }
                performUndoableChange("Detect Sections") {
                    applyDetectedSections(detected)
                }
            } catch {
                sectionDetectionError = error.localizedDescription
            }
        }
    }

    /// Replaces every marker. Clips are untouched.
    private func applyDetectedSections(_ detected: [ArrangementMarker]) {
        clearMarkerCue()
        timeline.markers = detected
        persistProjectState()
        syncPlayback()
        prepareSectionAnnouncements()
    }

    func beginRenameSection(_ section: SongSection) {
        activeSheet = .renameSection(section, title: "Rename Section")
    }

    func applySectionRename(_ newName: String, to section: SongSection) {
        activeSheet = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = timeline.markers.firstIndex(where: { $0.id == section.id }) else {
            return
        }

        commitTimelineEdit("Rename Section") { timeline in
            timeline.markers[index].name = trimmed
        }
    }

    /// Removes the marker only; the audio stays and joins the previous section.
    func removeMarker(_ section: SongSection) {
        if cuedSectionID == section.id {
            clearMarkerCue()
        }
        commitTimelineEdit("Remove Marker") { timeline in
            timeline.markers.removeAll { $0.id == section.id }
        }
    }

    /// Removes the section's span from every track, MIDI lane, and the marker list, closing the gap.
    private func deleteSection(_ section: SongSection) {
        if cuedSectionID == section.id {
            clearMarkerCue()
        }
        clipSelection.deselectAll()
        performUndoableChange("Delete Section") {
            ClipEditing.removeSection(section.id, timeline: &timeline, midiEvents: &midiEvents)
            persistProjectState()
            syncPlayback()
            reconfigureMIDI()
            prepareSectionAnnouncements()
        }
    }

    private func duplicateSection(_ sectionID: UUID) {
        clipSelection.deselectAll()
        performUndoableChange("Duplicate Section") {
            ClipEditing.duplicateSection(sectionID, timeline: &timeline, midiEvents: &midiEvents)
            persistProjectState()
            syncPlayback()
            reconfigureMIDI()
            prepareSectionAnnouncements()
        }
    }

    private func moveSection(_ sectionID: UUID, toIndex index: Int) {
        clearMarkerCue()
        clipSelection.deselectAll()
        performUndoableChange("Reorder Sections") {
            ClipEditing.moveSection(sectionID, toIndex: index, timeline: &timeline, midiEvents: &midiEvents)
            persistProjectState()
            syncPlayback()
            reconfigureMIDI()
            prepareSectionAnnouncements()
        }
    }

    var arrangementActions: ArrangementSectionActions {
        ArrangementSectionActions(
            sections: displaySections,
            move: moveSection(_:toIndex:),
            duplicate: duplicateSection,
            remove: { sectionID in
                guard let section = displaySections.first(where: { $0.id == sectionID }) else { return }
                deleteSection(section)
            }
        )
    }
}
