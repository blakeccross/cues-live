import Foundation
import Observation

/// Shared timing helpers for section-loop boundary detection.
enum SectionLoopTiming {
    /// Matches `AudioEngineManager`'s end-of-playback threshold so last-section
    /// loops fire before auto-stop zeros the playhead.
    static func sampleThreshold(sampleRate: Double) -> TimeInterval {
        1.0 / max(sampleRate, 1)
    }

    static func hasReachedBoundary(
        time: TimeInterval,
        sectionEnd: TimeInterval,
        sampleRate: Double
    ) -> Bool {
        time >= sectionEnd - sampleThreshold(sampleRate: sampleRate)
    }

    /// True when the looping section ends at (or within one sample of) song duration.
    static func sectionEndsAtSongEnd(
        sectionEnd: TimeInterval,
        songDuration: TimeInterval,
        sampleRate: Double
    ) -> Bool {
        sectionEnd >= songDuration - sampleThreshold(sampleRate: sampleRate)
    }
}

/// Tracks which arrangement section is actively looping during playback.
@Observable
final class SectionLoopController {
    private(set) var activeSectionID: UUID?
    /// Section the user is looping on demand, independent of the song's marked loop sections.
    private(set) var manualSectionID: UUID?
    private var suppressedSectionIDs: Set<UUID> = []

    var isLooping: Bool { activeSectionID != nil || manualSectionID != nil }

    func reset() {
        activeSectionID = nil
        manualSectionID = nil
        suppressedSectionIDs.removeAll()
    }

    /// Starts looping the given section regardless of whether it is a marked loop section.
    func beginManualLoop(sectionID: UUID) {
        manualSectionID = sectionID
        activeSectionID = nil
        suppressedSectionIDs.remove(sectionID)
    }

    func activeSection(
        in sections: [ArrangementDisplaySection],
        loopSlotIDs: Set<UUID>
    ) -> ArrangementDisplaySection? {
        if let manualSectionID,
           let section = sections.first(where: { $0.id == manualSectionID }) {
            return section
        }
        guard let activeSectionID,
              loopSlotIDs.contains(activeSectionID),
              let section = sections.first(where: { $0.id == activeSectionID }) else {
            return nil
        }
        return section
    }

    func handlePlaybackTimeChange(
        at time: TimeInterval,
        sections: [ArrangementDisplaySection],
        loopSlotIDs: Set<UUID>,
        onActivate: () -> Void
    ) {
        clearSuppressedSectionsIfOutsidePlayback(at: time, sections: sections)
        activateIfNeeded(at: time, sections: sections, loopSlotIDs: loopSlotIDs, onActivate: onActivate)
    }

    func handleLoopSlotIDsChange(_ loopSlotIDs: Set<UUID>) {
        if let activeSectionID, !loopSlotIDs.contains(activeSectionID) {
            self.activeSectionID = nil
        }
        suppressedSectionIDs = suppressedSectionIDs.intersection(loopSlotIDs)
    }

    @discardableResult
    func toggleLoop(on sectionID: UUID, loopSlotIDs: inout Set<UUID>) -> Bool {
        if loopSlotIDs.contains(sectionID) {
            loopSlotIDs.remove(sectionID)
            if activeSectionID == sectionID {
                activeSectionID = nil
            }
            suppressedSectionIDs.remove(sectionID)
            return false
        }

        loopSlotIDs.insert(sectionID)
        return true
    }

    func endLoop() {
        if let activeSectionID {
            suppressedSectionIDs.insert(activeSectionID)
        }
        if let manualSectionID {
            suppressedSectionIDs.insert(manualSectionID)
        }
        activeSectionID = nil
        manualSectionID = nil
    }

    func endLoopIfActive() {
        guard isLooping else { return }
        endLoop()
    }

    private func clearSuppressedSectionsIfOutsidePlayback(
        at time: TimeInterval,
        sections: [ArrangementDisplaySection]
    ) {
        guard !suppressedSectionIDs.isEmpty else { return }

        for sectionID in suppressedSectionIDs {
            guard let section = sections.first(where: { $0.id == sectionID }) else {
                suppressedSectionIDs.remove(sectionID)
                continue
            }
            if !section.containsTimelineTime(time) {
                suppressedSectionIDs.remove(sectionID)
            }
        }
    }

    private func activateIfNeeded(
        at time: TimeInterval,
        sections: [ArrangementDisplaySection],
        loopSlotIDs: Set<UUID>,
        onActivate: () -> Void
    ) {
        guard manualSectionID == nil, activeSectionID == nil, !loopSlotIDs.isEmpty else { return }

        guard let section = sections.loopSectionCandidate(
            at: time,
            loopSlotIDs: loopSlotIDs,
            suppressedSectionIDs: suppressedSectionIDs
        ) else {
            return
        }

        activeSectionID = section.id
        onActivate()
    }
}
