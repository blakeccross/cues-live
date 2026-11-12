import Foundation

/// Carries audio through a tempo edit for tracks locked to the tempo.
///
/// A locked track keeps every sound on the same beat. Each of its clips is cut wherever
/// either tempo map changes, each piece moves to where its beats now fall, and its playback
/// rate is set so the same stretch of file fills the new length. Unlocked tracks keep their
/// timeline position and speed. Section markers and MIDI cues follow the locked audio.
enum TempoTrackLock {
    /// Pieces shorter than this are rounding left over at a cut and are dropped.
    private static let minimumPieceSeconds: TimeInterval = 0.000_001
    /// Neighbouring pieces whose rates agree this closely play as one clip.
    private static let mergeRateTolerance = 0.000_000_001

    struct Result: Equatable {
        var timeline: SongTimeline
        var midiEvents: [MIDIEvent]
    }

    /// Re-times the locked tracks, plus markers and MIDI cues, from `old` to `new`.
    /// Returns the input unchanged when no track is locked.
    static func retime(
        _ timeline: SongTimeline,
        midiEvents: [MIDIEvent],
        lockedTrackIDs: Set<UUID>,
        from old: TempoTimeline,
        to new: TempoTimeline
    ) -> Result {
        guard !lockedTrackIDs.isEmpty, old != new else {
            return Result(timeline: timeline, midiEvents: midiEvents)
        }

        let cuts = cutTimes(from: old, to: new)
        var result = timeline
        result.clips = timeline.clips.flatMap { clip in
            lockedTrackIDs.contains(clip.trackID)
                ? retime(clip, cuts: cuts, from: old, to: new)
                : [clip]
        }
        result.markers = timeline.markers.map { marker in
            var moved = marker
            moved.startSeconds = position(marker.startSeconds, from: old, to: new)
            return moved
        }
        let movedEvents = midiEvents.map { event in
            var moved = event
            moved.timelineSeconds = position(event.timelineSeconds, from: old, to: new)
            return moved
        }
        return Result(timeline: result, midiEvents: movedEvents)
    }

    /// Where the beat at `seconds` under `old` falls under `new`.
    static func position(
        _ seconds: TimeInterval,
        from old: TempoTimeline,
        to new: TempoTimeline
    ) -> TimeInterval {
        guard seconds > 0 else { return seconds }
        return new.seconds(atFractionalTick: old.tick(atSeconds: seconds))
    }

    /// Old-timeline times where the ratio between the two maps can change: every event of either.
    private static func cutTimes(from old: TempoTimeline, to new: TempoTimeline) -> [TimeInterval] {
        let ticks = Set(old.points.map(\.tick)).union(new.points.map(\.tick))
        return ticks.map { old.seconds(atTick: $0) }.sorted()
    }

    private static func retime(
        _ clip: TrackClip,
        cuts: [TimeInterval],
        from old: TempoTimeline,
        to new: TempoTimeline
    ) -> [TrackClip] {
        let start = clip.timelineStartSeconds
        let end = clip.timelineEndSeconds
        let inner = cuts.filter { $0 > start + minimumPieceSeconds && $0 < end - minimumPieceSeconds }
        let bounds = [start] + inner + [end]

        var pieces: [TrackClip] = []
        for (lower, upper) in zip(bounds, bounds.dropFirst()) {
            let newStart = position(lower, from: old, to: new)
            let newEnd = position(upper, from: old, to: new)
            guard newEnd - newStart > minimumPieceSeconds else { continue }
            let rate = clip.playbackRate * (upper - lower) / (newEnd - newStart)

            if let last = pieces.last,
               abs(last.playbackRate - rate) <= mergeRateTolerance * rate,
               abs(last.timelineEndSeconds - newStart) <= minimumPieceSeconds {
                pieces[pieces.count - 1].duration = newEnd - last.timelineStartSeconds
                continue
            }
            pieces.append(
                TrackClip(
                    id: pieces.isEmpty ? clip.id : UUID(),
                    trackID: clip.trackID,
                    timelineStartSeconds: newStart,
                    duration: newEnd - newStart,
                    sourceStartSeconds: clip.sourceTime(atTimeline: lower),
                    gainDB: clip.gainDB,
                    playbackRate: rate
                )
            )
        }
        return pieces
    }
}
