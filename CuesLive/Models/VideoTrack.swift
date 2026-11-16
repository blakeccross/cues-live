import Foundation
import SwiftData

/// A movie that plays in the Video window in sync with the song. A song has at most one.
/// The file stays on disk and is referenced like a stem; the movie's own audio never plays.
@Model
final class VideoTrack {
    var id: UUID
    var displayName: String
    var mediaPath: String?
    var mediaPathStyleRaw: String?
    var mediaBookmarkData: Data?
    /// Timeline position of the movie's first frame. Negative starts the movie partway in.
    var startSeconds: Double = 0
    /// Length of the movie the last time it was readable, so the lane keeps its size when the file is missing.
    var sourceDurationSeconds: Double?
    /// Lane height in points. Missing or out-of-range values display at the default.
    var laneHeight: Double = TrackLaneHeight.storedDefault

    var song: Song?

    var mediaPathStyle: MediaPathStyle? {
        get {
            guard let mediaPathStyleRaw else { return nil }
            return MediaPathStyle(rawValue: mediaPathStyleRaw)
        }
        set {
            mediaPathStyleRaw = newValue?.rawValue
        }
    }

    var mediaReference: MediaReference? {
        get {
            guard let mediaPath, let mediaPathStyle else { return nil }
            return MediaReference(path: mediaPath, pathStyle: mediaPathStyle, bookmark: mediaBookmarkData)
        }
        set {
            mediaPath = newValue?.path
            mediaPathStyle = newValue?.pathStyle
            mediaBookmarkData = newValue?.bookmark
        }
    }

    init(displayName: String, media: MediaReference, startSeconds: Double = 0) {
        id = UUID()
        self.displayName = displayName
        mediaPath = media.path
        mediaPathStyleRaw = media.pathStyle.rawValue
        mediaBookmarkData = media.bookmark
        self.startSeconds = startSeconds
    }
}
