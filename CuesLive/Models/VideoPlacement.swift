import Foundation

/// Where a song's movie sits on its timeline. Timeline seconds map 1:1 to movie seconds.
struct VideoPlacement: Equatable, Sendable {
    let url: URL
    /// Timeline position of the movie's first frame.
    let startSeconds: TimeInterval
    /// Nil until the movie has been read; the picture then runs until the file ends.
    let durationSeconds: TimeInterval?

    /// Movie time shown at `timeline`, or nil before the movie starts or after it ends.
    func movieSeconds(atTimeline timeline: TimeInterval) -> TimeInterval? {
        let movie = timeline - startSeconds
        guard movie.isFinite, movie >= 0 else { return nil }
        if let durationSeconds, movie >= durationSeconds {
            return nil
        }
        return movie
    }
}

extension VideoPlacement {
    /// The song's movie placement, or nil when it has no video or the file cannot be found.
    init?(song: Song) {
        guard let video = song.videoTrack, let url = FileStore.videoURL(for: song) else { return nil }
        self.init(url: url, startSeconds: video.startSeconds, durationSeconds: video.sourceDurationSeconds)
    }
}
