import Foundation

struct CueAnnouncement: Equatable {
    let name: String
    let announceTime: TimeInterval
    let boundaryTime: TimeInterval
}

enum CueTrackScheduler {
    /// Schedules spoken section callouts one measure before each section boundary.
    /// Sections that start at (or extremely near) timeline zero are skipped, matching live cueing.
    static func scheduledAnnouncements(
        sections: [(name: String, startSeconds: TimeInterval)],
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> [CueAnnouncement] {
        let normalizedTempo = tempoChanges.normalizedEnsuringInitialMarker(
            defaultBPM: tempoChanges.referenceBPM
        )
        let normalizedSignatures = timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: MeasureTiming.defaultNumerator,
            defaultDenominator: MeasureTiming.defaultDenominator
        )

        var announcements: [CueAnnouncement] = []
        announcements.reserveCapacity(sections.count)

        for section in sections {
            let name = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard section.startSeconds > 0.001 else { continue }

            let lead = MeasureTiming.measureLeadDuration(
                endingAt: section.startSeconds,
                tempoChanges: normalizedTempo,
                timeSignatureChanges: normalizedSignatures
            )
            let announceTime = max(0, section.startSeconds - lead)
            announcements.append(
                CueAnnouncement(
                    name: name,
                    announceTime: announceTime,
                    boundaryTime: section.startSeconds
                )
            )
        }

        return announcements.sorted { lhs, rhs in
            if lhs.announceTime != rhs.announceTime {
                return lhs.announceTime < rhs.announceTime
            }
            return lhs.boundaryTime < rhs.boundaryTime
        }
    }
}
