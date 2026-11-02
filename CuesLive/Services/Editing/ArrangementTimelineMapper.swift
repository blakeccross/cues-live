import Foundation

/// Maps master-timeline seconds to absolute source-file seconds for one track.
struct ArrangementTimelineMapper: Sendable {
    private let sections: [ArrangementDisplaySection]
    private let trimStart: TimeInterval
    private let trimEnd: TimeInterval
    private let usesArrangement: Bool

    var hasArrangementMapping: Bool { usesArrangement && !sections.isEmpty }

    init(
        sections: [ArrangementDisplaySection],
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        usesArrangement: Bool
    ) {
        self.sections = sections.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.usesArrangement = usesArrangement
    }

    /// Fast-path bounds for tempo resampling when the master timeline maps 1:1 to source trim.
    func linearResampleBounds(
        atMasterTimeline master: TimeInterval,
        sampleRate: Double
    ) -> (startSourceFrame: Double, endSourceFrame: Double)? {
        guard !usesArrangement, sampleRate > 0 else { return nil }
        guard let sourceStart = sourceSeconds(atMasterTimeline: master) else { return nil }
        return (sourceStart * sampleRate, trimEnd * sampleRate)
    }

    /// Returns source-file seconds for the given master-timeline position, or nil when silent.
    func sourceSeconds(atMasterTimeline master: TimeInterval) -> TimeInterval? {
        let rawSource: TimeInterval?
        if usesArrangement {
            guard let section = section(containing: master) else {
                return nil
            }
            let offset = master - section.timelineStartSeconds
            rawSource = section.sourceStartSeconds + offset
        } else {
            rawSource = trimStart + master
        }

        guard let rawSource else { return nil }
        let clamped = max(rawSource, trimStart)
        guard clamped < trimEnd else { return nil }
        return clamped
    }

    /// Master-timeline seconds until the current mapping region ends (section, trim, or buffer limit).
    func regionRemainingSeconds(fromMasterTimeline master: TimeInterval, bufferLimit: TimeInterval) -> TimeInterval {
        let limit = max(0, bufferLimit)
        guard limit > 0 else { return 0 }

        if usesArrangement {
            guard let section = section(containing: master) else {
                if let next = sections.first(where: { $0.timelineStartSeconds > master }) {
                    let gapRemaining = next.timelineStartSeconds - master
                    return max(0, min(limit, gapRemaining))
                }
                return 0
            }

            let sectionRemaining = section.timelineEndSeconds - master
            let sourceAtMaster = section.sourceStartSeconds + (master - section.timelineStartSeconds)
            let trimRemaining = trimEnd - sourceAtMaster
            return max(0, min(limit, sectionRemaining, trimRemaining))
        }

        let trimRemaining = trimEnd - (trimStart + master)
        return max(0, min(limit, trimRemaining))
    }

    private func section(containing master: TimeInterval) -> ArrangementDisplaySection? {
        guard !sections.isEmpty else { return nil }

        var low = 0
        var high = sections.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let candidate = sections[mid]

            if master < candidate.timelineStartSeconds {
                high = mid - 1
            } else if master >= candidate.timelineEndSeconds {
                low = mid + 1
            } else {
                return candidate
            }
        }

        return nil
    }
}
