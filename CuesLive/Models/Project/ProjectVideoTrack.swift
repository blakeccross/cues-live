import Foundation

/// The song's movie as stored in a `.cueslive` file.
struct ProjectVideoTrack: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var media: MediaReference
    var startSeconds: Double
    var sourceDurationSeconds: Double?
    var laneHeight: Double

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
}
