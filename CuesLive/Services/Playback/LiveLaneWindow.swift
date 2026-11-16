import CoreGraphics
import Foundation

/// The stretch of a song a setlist lane shows: the in point at the lane's leading edge and the
/// out point at its trailing edge. Times stay on the song's timeline, so the playhead, seeks and
/// section cues need no conversion; only placement on the lane goes through the window.
struct LiveLaneWindow: Equatable, Sendable {
    /// The in point.
    let start: TimeInterval
    /// The out point.
    let end: TimeInterval

    private static let minimumDuration: TimeInterval = 0.001

    init(start: TimeInterval = 0, end: TimeInterval) {
        self.start = max(0, start)
        self.end = max(end, self.start + Self.minimumDuration)
    }

    /// Length of the lane, in seconds.
    var duration: TimeInterval { end - start }

    /// Lane x of a timeline time. Times outside the window pin to the lane's ends.
    func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        TimelineLayout.xPosition(for: clamped(time) - start, duration: duration, contentWidth: width)
    }

    /// Timeline time under lane x.
    func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        start + TimelineLayout.time(at: x, duration: duration, contentWidth: width)
    }

    func clamped(_ time: TimeInterval) -> TimeInterval {
        min(max(time, start), end)
    }

    /// Clips cut to the window and moved so the in point is time zero, for drawing the waveform
    /// across the lane. Clips wholly outside the window are dropped.
    func laneClips(_ clips: [TrackClip]) -> [TrackClip] {
        clips.compactMap { clip in
            let lower = max(clip.timelineStartSeconds, start)
            let upper = min(clip.timelineEndSeconds, end)
            guard upper > lower else { return nil }
            var cut = clip
            cut.sourceStartSeconds += (lower - clip.timelineStartSeconds) * clip.playbackRate
            cut.timelineStartSeconds = lower - start
            cut.duration = upper - lower
            return cut
        }
    }
}
