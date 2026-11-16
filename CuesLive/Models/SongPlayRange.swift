import Foundation

/// Where a song starts and stops playing. Independent of the clips: moving a point changes which
/// stretch of the timeline plays, never the audio.
struct SongPlayRange: Codable, Hashable, Sendable {
    /// Shortest span the in and out points can enclose.
    static let minimumLength: TimeInterval = 0.5

    /// The in point, in timeline seconds.
    var startSeconds: TimeInterval
    /// The out point. Nil follows the end of the song's content.
    var endSeconds: TimeInterval?

    init(startSeconds: TimeInterval = 0, endSeconds: TimeInterval? = nil) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    enum Point: Sendable {
        case start
        case end
    }

    /// The in and out points against a song whose content ends at `songEnd`. The in point stays
    /// at or after zero, and the out point at least `minimumLength` after it.
    func resolved(songEnd: TimeInterval) -> ClosedRange<TimeInterval> {
        let start = max(0, startSeconds)
        let end = max(endSeconds ?? songEnd, start + Self.minimumLength)
        return start...end
    }

    /// The range after dragging `point` to `time`. The dragged point stops `minimumLength` short
    /// of the other one and never moves before zero or past `limit`.
    func moving(
        _ point: Point,
        to time: TimeInterval,
        songEnd: TimeInterval,
        limit: TimeInterval
    ) -> SongPlayRange {
        let current = resolved(songEnd: songEnd)
        switch point {
        case .start:
            let upper = max(0, current.upperBound - Self.minimumLength)
            return SongPlayRange(startSeconds: min(max(0, time), upper), endSeconds: endSeconds)
        case .end:
            let lower = current.lowerBound + Self.minimumLength
            return SongPlayRange(startSeconds: startSeconds, endSeconds: max(min(time, limit), lower))
        }
    }
}
