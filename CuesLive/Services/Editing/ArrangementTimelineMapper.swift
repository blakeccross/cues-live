import Foundation

/// Maps master-timeline seconds to absolute source-file seconds for one track.
///
/// Arranged tracks play their clips; between clips they are silent. Linear tracks
/// play the file from `trimStart` at master time zero.
///
/// Clips re-timed by a tempo change read their file faster or slower; the track's
/// `LiveStretcher` keeps them at their original pitch.
struct ArrangementTimelineMapper: Sendable {
    private let clips: [TrackClip]
    private let sourceStart: TimeInterval
    private let sourceEnd: TimeInterval
    private let usesClips: Bool
    /// True when any clip plays away from its original speed, so the track needs a stretcher.
    let hasRetimedClips: Bool

    init(clips: [TrackClip], fileDuration: TimeInterval) {
        self.clips = clips.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        sourceStart = 0
        sourceEnd = fileDuration
        usesClips = true
        hasRetimedClips = clips.contains { !$0.playsAtOriginalSpeed }
    }

    private init(trimStart: TimeInterval, trimEnd: TimeInterval) {
        clips = []
        sourceStart = trimStart
        sourceEnd = trimEnd
        usesClips = false
        hasRetimedClips = false
    }

    static func linear(trimStart: TimeInterval = 0, trimEnd: TimeInterval) -> ArrangementTimelineMapper {
        ArrangementTimelineMapper(trimStart: max(0, trimStart), trimEnd: trimEnd)
    }

    /// Returns source-file seconds for the given master-timeline position, or nil when silent.
    func sourceSeconds(atMasterTimeline master: TimeInterval) -> TimeInterval? {
        let rawSource: TimeInterval
        if usesClips {
            guard let clip = clip(containing: master) else { return nil }
            rawSource = clip.sourceTime(atTimeline: master)
        } else {
            rawSource = sourceStart + master
        }

        let clamped = max(rawSource, sourceStart)
        guard clamped < sourceEnd else { return nil }
        return clamped
    }

    /// Master-timeline seconds until the current mapping region ends (clip, file end, or buffer limit).
    func regionRemainingSeconds(fromMasterTimeline master: TimeInterval, bufferLimit: TimeInterval) -> TimeInterval {
        let limit = max(0, bufferLimit)
        guard limit > 0 else { return 0 }

        if usesClips {
            guard let clip = clip(containing: master) else {
                if let next = clips.first(where: { $0.timelineStartSeconds > master }) {
                    return max(0, min(limit, next.timelineStartSeconds - master))
                }
                return 0
            }
            let clipRemaining = clip.timelineEndSeconds - master
            let fileRemaining = (sourceEnd - clip.sourceTime(atTimeline: master)) / clip.playbackRate
            return max(0, min(limit, clipRemaining, fileRemaining))
        }

        return max(0, min(limit, sourceEnd - (sourceStart + master)))
    }

    /// Playback positions are snapped to whole frames, so a jump to a clip can land up to
    /// half a frame before the clip's exact start. Without slack that position falls in
    /// a gap, nothing is mapped, and the block that should open on the clip's first
    /// click renders silent. About one frame at 48 kHz, far below anything audible.
    private static let boundaryTolerance: TimeInterval = 2e-5

    func clip(containing time: TimeInterval) -> TrackClip? {
        guard !clips.isEmpty else { return nil }
        let master = time + Self.boundaryTolerance

        var low = 0
        var high = clips.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let candidate = clips[mid]

            if master < candidate.timelineStartSeconds {
                high = mid - 1
            } else if master >= candidate.timelineEndSeconds {
                low = mid + 1
            } else {
                return candidate
            }
        }

        return nil
    }

    /// Source seconds read per timeline second at `master`. Unity outside clips.
    func playbackRate(atMasterTimeline master: TimeInterval) -> Double {
        guard usesClips, let clip = clip(containing: master) else { return 1 }
        return clip.playbackRate
    }

    /// Clip gain at `master`, or unity where the track is not playing arranged clips.
    func linearGain(atMasterTimeline master: TimeInterval) -> Float {
        guard usesClips, let clip = clip(containing: master) else { return 1 }
        return clip.linearGain
    }
}
