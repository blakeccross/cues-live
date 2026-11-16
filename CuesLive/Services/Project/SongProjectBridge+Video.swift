import Foundation
import SwiftData

extension SongProjectBridge {
    static func projectVideoTrack(for song: Song) -> ProjectVideoTrack? {
        guard let video = song.videoTrack, let media = video.mediaReference else { return nil }
        return ProjectVideoTrack(
            id: video.id,
            displayName: video.displayName,
            media: media,
            startSeconds: video.startSeconds,
            sourceDurationSeconds: video.sourceDurationSeconds,
            laneHeight: video.laneHeight
        )
    }

    /// Replaces the song's movie with the document's, or removes it when the document has none.
    static func applyVideo(_ projectVideo: ProjectVideoTrack?, to song: Song, context: ModelContext) {
        if let existing = song.videoTrack {
            song.videoTrack = nil
            context.delete(existing)
        }
        guard let projectVideo else { return }
        let video = VideoTrack(
            displayName: projectVideo.displayName,
            media: projectVideo.media,
            startSeconds: projectVideo.startSeconds
        )
        video.id = projectVideo.id
        video.sourceDurationSeconds = projectVideo.sourceDurationSeconds
        video.laneHeight = projectVideo.laneHeight
        video.song = song
        context.insert(video)
        song.videoTrack = video
    }
}
