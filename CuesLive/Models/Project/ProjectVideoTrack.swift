import Foundation

/// The song's movie as stored in a `.cueslive` file. Absent in files written before video support.
struct ProjectVideoTrack: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var media: MediaReference
    var startSeconds: Double
    var sourceDurationSeconds: Double?
    var laneHeight: Double

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case media
        case startSeconds
        case sourceDurationSeconds
        case laneHeight
    }

    init(
        id: UUID,
        displayName: String,
        media: MediaReference,
        startSeconds: Double = 0,
        sourceDurationSeconds: Double? = nil,
        laneHeight: Double = TrackLaneHeight.storedDefault
    ) {
        self.id = id
        self.displayName = displayName
        self.media = media
        self.startSeconds = startSeconds
        self.sourceDurationSeconds = sourceDurationSeconds
        self.laneHeight = laneHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        media = try container.decode(MediaReference.self, forKey: .media)
        startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0
        sourceDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds)
        laneHeight = try container.decodeIfPresent(Double.self, forKey: .laneHeight) ?? TrackLaneHeight.storedDefault
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(media, forKey: .media)
        try container.encode(startSeconds, forKey: .startSeconds)
        try container.encodeIfPresent(sourceDurationSeconds, forKey: .sourceDurationSeconds)
        try container.encode(laneHeight, forKey: .laneHeight)
    }
}
