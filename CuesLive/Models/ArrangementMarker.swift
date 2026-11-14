import Foundation

/// A named point on the song timeline. The section it starts runs until the next marker, or
/// until `endSeconds` when that comes first.
struct ArrangementMarker: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Timeline position. Format-2 projects stored source-file time here; migration converts it.
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startSeconds = try container.decode(Double.self, forKey: .startSeconds)
        endSeconds = try container.decodeIfPresent(Double.self, forKey: .endSeconds)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        loops = try container.decodeIfPresent(Bool.self, forKey: .loops) ?? false
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
