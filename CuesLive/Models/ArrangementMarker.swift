import Foundation

/// A named point on the song timeline. The section it starts runs until the next marker, or
/// until `endSeconds` when that comes first.
struct ArrangementMarker: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Timeline position.
    var startSeconds: Double
    /// Where the section ends when it stops short of the next marker. Nil runs to the next marker.
    var endSeconds: Double?
    var sortOrder: Int
    /// Live playback loops this marker's section until released.
    var loops: Bool

    init(
        id: UUID = UUID(),
        name: String,
        startSeconds: Double,
        endSeconds: Double? = nil,
        sortOrder: Int = 0,
        loops: Bool = false
    ) {
        self.id = id
        self.name = name
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.sortOrder = sortOrder
        self.loops = loops
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
