import Foundation

/// A drag on one edge of a section block in the editor's marker ruler.
enum SectionEdgeEdit: Equatable, Sendable {
    /// Moves the section's marker. Unless `independent`, a previous section that runs up to this
    /// marker keeps running up to it; when `independent`, every other section keeps its span.
    case start(sectionID: UUID, time: TimeInterval, independent: Bool)
    /// Ends the section early, leaving a gap before the next marker. Ending it on the next marker
    /// or the song end makes it run there again.
    case end(sectionID: UUID, time: TimeInterval)
}

extension SongTimeline {
    /// Shortest section an edge edit may leave.
    static let minimumSectionLength: TimeInterval = 0.1

    private static let edgeTolerance: TimeInterval = 0.000_1

    /// Applies an edge drag, clamped so sections never overlap or drop below
    /// `minimumSectionLength`. Returns false when the section is missing or nothing changed.
    @discardableResult
    mutating func apply(_ edit: SectionEdgeEdit, songEnd: TimeInterval) -> Bool {
        switch edit {
        case let .start(id, time, independent):
            return moveSectionStart(id, to: time, independent: independent, songEnd: songEnd)
        case let .end(id, time):
            return moveSectionEnd(id, to: time, songEnd: songEnd)
        }
    }

    func applying(_ edit: SectionEdgeEdit, songEnd: TimeInterval) -> SongTimeline {
        var edited = self
        edited.apply(edit, songEnd: songEnd)
        return edited
    }

    private mutating func moveSectionStart(
        _ id: UUID,
        to time: TimeInterval,
        independent: Bool,
        songEnd: TimeInterval
    ) -> Bool {
        let sorted = sortedMarkers
        guard let position = sorted.firstIndex(where: { $0.id == id }),
              let index = markers.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let oldStart = sorted[position].startSeconds
        let previous = position > 0 ? sorted[position - 1] : nil
        let previousEnd = previous.map { _ in sectionEnd(at: position - 1, in: sorted, songEnd: songEnd) }
        let previousFollows = previousEnd.map { abs($0 - oldStart) <= Self.edgeTolerance } ?? false

        let lower: TimeInterval
        if let previous, previousFollows, !independent {
            lower = previous.startSeconds + Self.minimumSectionLength
        } else {
            lower = previousEnd ?? 0
        }
        let upper = sectionEnd(at: position, in: sorted, songEnd: songEnd) - Self.minimumSectionLength
        guard upper >= lower else { return false }
        let clamped = min(max(time, lower), upper)
        guard abs(clamped - oldStart) > Self.edgeTolerance else { return false }

        if let previous, previousFollows, let previousIndex = markers.firstIndex(where: { $0.id == previous.id }) {
            // Independent: pin the previous end where it was. Linked: let it follow the marker.
            markers[previousIndex].endSeconds = independent ? oldStart : nil
        }
        markers[index].startSeconds = clamped
        return true
    }

    private mutating func moveSectionEnd(_ id: UUID, to time: TimeInterval, songEnd: TimeInterval) -> Bool {
        let sorted = sortedMarkers
        guard let position = sorted.firstIndex(where: { $0.id == id }),
              let index = markers.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let limit = position + 1 < sorted.count ? sorted[position + 1].startSeconds : songEnd
        let lower = sorted[position].startSeconds + Self.minimumSectionLength
        guard limit >= lower else { return false }
        let clamped = min(max(time, lower), limit)
        let oldEnd = sectionEnd(at: position, in: sorted, songEnd: songEnd)
        guard abs(clamped - oldEnd) > Self.edgeTolerance else { return false }

        markers[index].endSeconds = abs(clamped - limit) <= Self.edgeTolerance ? nil : clamped
        return true
    }

    private func sectionEnd(at position: Int, in sorted: [ArrangementMarker], songEnd: TimeInterval) -> TimeInterval {
        let limit = position + 1 < sorted.count ? sorted[position + 1].startSeconds : songEnd
        return min(sorted[position].endSeconds ?? limit, limit)
    }
}
