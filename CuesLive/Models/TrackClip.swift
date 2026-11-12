import Foundation

/// A span of one track's audio file placed on the song timeline. Clips belong only to their
/// track; sections never constrain or own them.
struct TrackClip: Codable, Hashable, Identifiable, Sendable {
    static let minimumDuration: TimeInterval = 0.1
    static let validRateRange = 0.05...20.0
    static let rateTolerance = 0.000_1

    let id: UUID
    var trackID: UUID
    var timelineStartSeconds: TimeInterval
    var duration: TimeInterval
    /// Offset into the track's audio file where this clip starts playing.
    var sourceStartSeconds: TimeInterval
    /// Static clip gain in decibels. 0 is unity. The audio file stays unchanged.
    var gainDB: Double
    /// Source seconds played per timeline second. Above 1 the audio plays faster, at its
    /// original pitch. Set when a tempo change re-times a track locked to the tempo.
    var playbackRate: Double

    init(
        id: UUID = UUID(),
        trackID: UUID,
        timelineStartSeconds: TimeInterval,
        duration: TimeInterval,
        sourceStartSeconds: TimeInterval,
        gainDB: Double = 0,
        playbackRate: Double = 1
    ) {
        self.id = id
        self.trackID = trackID
        self.timelineStartSeconds = timelineStartSeconds
        self.duration = duration
        self.sourceStartSeconds = sourceStartSeconds
        self.gainDB = ClipGain.stored(gainDB)
        self.playbackRate = Self.storedRate(playbackRate)
    }

    var timelineEndSeconds: TimeInterval { timelineStartSeconds + duration }
    var sourceEndSeconds: TimeInterval { sourceStartSeconds + sourceDuration }
    /// Length of the stretch of file the clip plays.
    var sourceDuration: TimeInterval { duration * playbackRate }

    /// Plays at the file's own speed.
    var playsAtOriginalSpeed: Bool { abs(playbackRate - 1) < Self.rateTolerance }

    func containsTimelineTime(_ time: TimeInterval) -> Bool {
        time >= timelineStartSeconds && time < timelineEndSeconds
    }

    func sourceTime(atTimeline time: TimeInterval) -> TimeInterval {
        sourceStartSeconds + (time - timelineStartSeconds) * playbackRate
    }

    /// Timeline seconds at which the clip's stretch of file would reach `source`.
    func timelineTime(atSource source: TimeInterval) -> TimeInterval {
        timelineStartSeconds + (source - sourceStartSeconds) / playbackRate
    }

    /// True when `next` picks up the file exactly where this clip leaves it, at the same speed.
    func continues(into next: TrackClip, tolerance: TimeInterval) -> Bool {
        abs(next.playbackRate - playbackRate) < Self.rateTolerance
            && abs(sourceTime(atTimeline: next.timelineStartSeconds) - next.sourceStartSeconds) <= tolerance
    }

    private static func storedRate(_ rate: Double) -> Double {
        guard rate.isFinite else { return 1 }
        return min(max(rate, validRateRange.lowerBound), validRateRange.upperBound)
    }

    /// Linear amplitude for `gainDB`. −144 dB and below is silence.
    var linearGain: Float {
        ClipGain.linearGain(decibels: gainDB)
    }

    /// The whole file placed at the start of the timeline.
    static func wholeFile(trackID: UUID, duration: TimeInterval) -> TrackClip {
        TrackClip(trackID: trackID, timelineStartSeconds: 0, duration: duration, sourceStartSeconds: 0)
    }

    /// The trimmed stretch of a source file, placed at `timelineStart`.
    /// A start before the timeline is moved to zero. Nil when the trim is shorter than a clip.
    static func placed(
        trackID: UUID,
        sourceDuration: TimeInterval,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval? = nil,
        timelineStart: TimeInterval = 0
    ) -> TrackClip? {
        let start = min(max(trimStart, 0), sourceDuration)
        let end = min(trimEnd ?? sourceDuration, sourceDuration)
        guard end - start >= minimumDuration else { return nil }
        return TrackClip(
            trackID: trackID,
            timelineStartSeconds: max(0, timelineStart),
            duration: end - start,
            sourceStartSeconds: start
        )
    }
}

extension TrackClip {
    private enum CodingKeys: String, CodingKey {
        case id
        case trackID
        case timelineStartSeconds
        case duration
        case sourceStartSeconds
        case gainDB
        case playbackRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            trackID: try container.decode(UUID.self, forKey: .trackID),
            timelineStartSeconds: try container.decode(TimeInterval.self, forKey: .timelineStartSeconds),
            duration: try container.decode(TimeInterval.self, forKey: .duration),
            sourceStartSeconds: try container.decode(TimeInterval.self, forKey: .sourceStartSeconds),
            gainDB: try container.decodeIfPresent(Double.self, forKey: .gainDB) ?? 0,
            playbackRate: try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(timelineStartSeconds, forKey: .timelineStartSeconds)
        try container.encode(duration, forKey: .duration)
        try container.encode(sourceStartSeconds, forKey: .sourceStartSeconds)
        try container.encode(gainDB, forKey: .gainDB)
        try container.encode(playbackRate, forKey: .playbackRate)
    }
}
