import Foundation

struct ArrangementMarker: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let startSeconds: Double
    let sortOrder: Int

    init(id: UUID = UUID(), name: String, startSeconds: Double, sortOrder: Int) {
        self.id = id
        self.name = name
        self.startSeconds = startSeconds
        self.sortOrder = sortOrder
    }
}

extension Array where Element == ArrangementMarker {
    var sortedByTime: [ArrangementMarker] {
        sorted {
            if $0.startSeconds != $1.startSeconds {
                return $0.startSeconds < $1.startSeconds
            }
            return $0.sortOrder < $1.sortOrder
        }
    }
}

/// Marker edits for a dragged section range.
///
/// A section runs from its marker until the next marker. Creating one with an
/// explicit end inserts the start marker and, when needed, a marker at the end
/// so the following music keeps the name it already had.
struct SectionRangeInsertion: Equatable {
    var markers: [ArrangementMarker]
    var sectionMarkerID: UUID
    var removedMarkerIDs: [UUID]

    static let boundaryTolerance: TimeInterval = 0.02
    static let minimumDuration: TimeInterval = 0.05

    static func plan(
        markers: [ArrangementMarker],
        start: TimeInterval,
        end: TimeInterval,
        songDuration: TimeInterval,
        newSectionName: String
    ) -> SectionRangeInsertion? {
        let sorted = markers.sortedByTime
        let duration = max(songDuration, 0)
        let rangeStart = min(max(0, start), duration)
        let rangeEnd = min(max(0, end), duration)
        guard rangeEnd - rangeStart >= minimumDuration else { return nil }

        let endsAtSongEnd = duration > 0 && abs(rangeEnd - duration) < boundaryTolerance
        let endsOnMarker = sorted.contains { abs($0.startSeconds - rangeEnd) < boundaryTolerance }

        let removed = sorted.filter { marker in
            marker.startSeconds > rangeStart + boundaryTolerance
                && marker.startSeconds < rangeEnd - boundaryTolerance
        }
        let removedIDs = Set(removed.map(\.id))
        var kept = sorted.filter { !removedIDs.contains($0.id) }

        let sectionMarker: ArrangementMarker
        if let existing = kept.first(where: { abs($0.startSeconds - rangeStart) < boundaryTolerance }) {
            sectionMarker = existing
        } else {
            sectionMarker = ArrangementMarker(
                name: newSectionName,
                startSeconds: rangeStart,
                sortOrder: kept.count
            )
            kept.append(sectionMarker)
        }

        if !endsAtSongEnd, !endsOnMarker {
            let probe = max(rangeStart, rangeEnd - boundaryTolerance)
            let trailingName = sectionName(containing: probe, in: sorted) ?? ""
            kept.append(
                ArrangementMarker(
                    name: trailingName,
                    startSeconds: rangeEnd,
                    sortOrder: kept.count
                )
            )
        }

        let ordered = kept.sortedByTime.enumerated().map { index, marker in
            ArrangementMarker(
                id: marker.id,
                name: marker.name,
                startSeconds: marker.startSeconds,
                sortOrder: index
            )
        }

        return SectionRangeInsertion(
            markers: ordered,
            sectionMarkerID: sectionMarker.id,
            removedMarkerIDs: removed.map(\.id)
        )
    }

    /// Name of the section that owns `time`, using the markers from before the edit.
    private static func sectionName(
        containing time: TimeInterval,
        in sorted: [ArrangementMarker]
    ) -> String? {
        guard let index = sorted.lastIndex(where: { $0.startSeconds <= time + 0.001 }) else {
            return nil
        }
        return sorted[index].name
    }
}
