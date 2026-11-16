import Foundation
import SwiftData

/// The song's movie as captured for undo.
struct VideoTrackEditSnapshot: Equatable, Hashable {
    let id: UUID
    var displayName: String
    var mediaPath: String?
    var mediaPathStyleRaw: String?
    var mediaBookmarkData: Data?
    var startSeconds: Double
    var sourceDurationSeconds: Double?
    var laneHeight: Double

    init(video: VideoTrack) {
        id = video.id
        displayName = video.displayName
        mediaPath = video.mediaPath
        mediaPathStyleRaw = video.mediaPathStyleRaw
        mediaBookmarkData = video.mediaBookmarkData
        startSeconds = video.startSeconds
        sourceDurationSeconds = video.sourceDurationSeconds
        laneHeight = video.laneHeight
    }

    func apply(to video: VideoTrack) {
        video.displayName = displayName
        video.mediaPath = mediaPath
        video.mediaPathStyleRaw = mediaPathStyleRaw
        video.mediaBookmarkData = mediaBookmarkData
        video.startSeconds = startSeconds
        video.sourceDurationSeconds = sourceDurationSeconds
        video.laneHeight = laneHeight
    }
}

extension SongEditSnapshot {
    /// Restores the captured movie, re-creating it after a removal or removing it after an add.
    func applyVideo(to song: Song, context: ModelContext) {
        if let existing = song.videoTrack, existing.id != video?.id {
            song.videoTrack = nil
            context.delete(existing)
        }
        guard let video else { return }
        if let existing = song.videoTrack {
            video.apply(to: existing)
            return
        }
        let restored = VideoTrack(
            displayName: video.displayName,
            media: MediaReference(path: "", pathStyle: .absolute)
        )
        restored.id = video.id
        video.apply(to: restored)
        restored.song = song
        context.insert(restored)
        song.videoTrack = restored
    }
}
