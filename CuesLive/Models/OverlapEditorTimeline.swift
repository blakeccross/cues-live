import Foundation

/// The overlap editor's shared time axis, in seconds from the outgoing song's in point. The incoming
/// song enters `startOffsetSeconds` before the outgoing song's out point. The editor lays both
/// lanes out on it, and the preview plays along it.
struct OverlapEditorTimeline: Equatable {
    /// The outgoing song's in and out points, on its own timeline.
    let outgoingRange: ClosedRange<TimeInterval>
    /// The incoming song's in and out points, on its own timeline.
    let incomingRange: ClosedRange<TimeInterval>
    /// How long both songs play together. Never longer than either song.
    let startOffsetSeconds: TimeInterval

    init(
        outgoingRange: ClosedRange<TimeInterval>,
        incomingRange: ClosedRange<TimeInterval>,
        startOffsetSeconds: TimeInterval
    ) {
        self.outgoingRange = outgoingRange
        self.incomingRange = incomingRange
        self.startOffsetSeconds = Self.clampedStartOffset(
            startOffsetSeconds,
            outgoingLength: outgoingRange.upperBound - outgoingRange.lowerBound,
            incomingLength: incomingRange.upperBound - incomingRange.lowerBound
        )
    }

    var outgoingLength: TimeInterval {
        outgoingRange.upperBound - outgoingRange.lowerBound
    }

    var incomingLength: TimeInterval {
        incomingRange.upperBound - incomingRange.lowerBound
    }

    /// Editor time where the incoming song starts.
    var incomingEntry: TimeInterval {
        outgoingLength - startOffsetSeconds
    }

    /// Editor time where the later of the two songs ends.
    var duration: TimeInterval {
        max(outgoingLength, incomingEntry + incomingLength)
    }

    /// Middle of the span where both songs play.
    var transitionCenter: TimeInterval {
        incomingEntry + startOffsetSeconds / 2
    }

    /// The stretch the editor shows: from `margin` seconds before the incoming song enters to
    /// `margin` seconds after the outgoing song ends, kept within the songs.
    func focusRange(margin: TimeInterval) -> ClosedRange<TimeInterval> {
        let lower = max(0, incomingEntry - margin)
        let upper = max(lower, min(duration, outgoingLength + margin))
        return lower...upper
    }

    /// The outgoing song's own time at `editorTime`, or `nil` outside the song.
    func outgoingTime(at editorTime: TimeInterval) -> TimeInterval? {
        guard editorTime >= 0, editorTime < outgoingLength else { return nil }
        return outgoingRange.lowerBound + editorTime
    }

    /// The incoming song's own time at `editorTime`, or `nil` outside the song.
    func incomingTime(at editorTime: TimeInterval) -> TimeInterval? {
        let local = editorTime - incomingEntry
        guard local >= 0, local < incomingLength else { return nil }
        return incomingRange.lowerBound + local
    }

    func editorTime(outgoingTime: TimeInterval) -> TimeInterval {
        outgoingTime - outgoingRange.lowerBound
    }

    func editorTime(incomingTime: TimeInterval) -> TimeInterval {
        incomingEntry + incomingTime - incomingRange.lowerBound
    }

    /// The start offset that makes the incoming song enter at editor time `entry`.
    func startOffset(incomingEntry entry: TimeInterval) -> TimeInterval {
        Self.clampedStartOffset(
            outgoingLength - entry,
            outgoingLength: outgoingLength,
            incomingLength: incomingLength
        )
    }

    static func clampedStartOffset(
        _ offset: TimeInterval,
        outgoingLength: TimeInterval,
        incomingLength: TimeInterval
    ) -> TimeInterval {
        max(0, min(offset, outgoingLength, incomingLength))
    }
}
