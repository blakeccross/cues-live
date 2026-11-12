import Foundation

/// Markers and clips for one song.
struct SongTimeline: Codable, Hashable {
    var markers: [ArrangementMarker]
    var clips: [TrackClip]

    init(markers: [ArrangementMarker] = [], clips: [TrackClip] = []) {
        self.markers = markers
        self.clips = clips
    }

    var sortedMarkers: [ArrangementMarker] {
        markers.sortedByTime
    }

    func clips(forTrack trackID: UUID) -> [TrackClip] {
        clips
            .filter { $0.trackID == trackID }
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
    }

    var clipsByTrack: [UUID: [TrackClip]] {
        Dictionary(grouping: clips, by: \.trackID)
            .mapValues { $0.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds } }
    }

    /// End of the last clip on any track.
    var contentEnd: TimeInterval {
        clips.map(\.timelineEndSeconds).max() ?? 0
    }

    /// Playable length: the last clip, or the last marker when it sits past every clip.
    var duration: TimeInterval {
        max(contentEnd, markers.map(\.startSeconds).max() ?? 0)
    }

    func sections(songEnd: TimeInterval? = nil) -> [SongSection] {
        SongSection.derive(markers: markers, songEnd: songEnd ?? contentEnd)
    }
}

/// The span from one marker to the next. Derived on demand; never stored.
struct SongSection: Identifiable, Hashable, Sendable {
    /// The starting marker's ID.
    let id: UUID
    let name: String
    let timelineStartSeconds: TimeInterval
    let timelineEndSeconds: TimeInterval
    let loops: Bool

    var duration: TimeInterval { timelineEndSeconds - timelineStartSeconds }

    func containsTimelineTime(_ time: TimeInterval) -> Bool {
        time >= timelineStartSeconds && time < timelineEndSeconds
    }

    /// The last section ends at `songEnd`; sections that would start at or after it are dropped.
    static func derive(markers: [ArrangementMarker], songEnd: TimeInterval) -> [SongSection] {
        let sorted = markers.sortedByTime
        return sorted.enumerated().compactMap { index, marker in
            let end = index + 1 < sorted.count ? sorted[index + 1].startSeconds : songEnd
            guard end > marker.startSeconds else { return nil }
            return SongSection(
                id: marker.id,
                name: marker.name,
                timelineStartSeconds: marker.startSeconds,
                timelineEndSeconds: end,
                loops: marker.loops
            )
        }
    }
}

extension Array where Element == SongSection {
    func section(atTimeline time: TimeInterval) -> SongSection? {
        first { $0.containsTimelineTime(time) }
    }

    var loopSectionIDs: Set<UUID> {
        Set(filter(\.loops).map(\.id))
    }

    func loopSectionCandidate(
        at time: TimeInterval,
        loopSectionIDs: Set<UUID>,
        suppressedSectionIDs: Set<UUID>
    ) -> SongSection? {
        first {
            loopSectionIDs.contains($0.id)
                && !suppressedSectionIDs.contains($0.id)
                && $0.containsTimelineTime(time)
        }
    }
}

/// Everything playback needs from a song's timeline.
struct SongPlaybackLayout: Equatable {
    let clipsByTrack: [UUID: [TrackClip]]
    let sections: [SongSection]
    let duration: TimeInterval

    init(timeline: SongTimeline) {
        clipsByTrack = timeline.clipsByTrack
        duration = timeline.duration
        sections = timeline.sections(songEnd: duration)
    }

    init(clipsByTrack: [UUID: [TrackClip]] = [:], sections: [SongSection] = [], duration: TimeInterval? = nil) {
        self.clipsByTrack = clipsByTrack
        self.sections = sections
        let clipEnd = clipsByTrack.values.flatMap { $0 }.map(\.timelineEndSeconds).max() ?? 0
        self.duration = duration ?? max(clipEnd, sections.last?.timelineEndSeconds ?? 0)
    }

    /// Clips used to map a single combined waveform onto the timeline.
    var peakClips: [TrackClip] {
        let covered = { (clips: [TrackClip]) in clips.reduce(0) { $0 + $1.duration } }
        return clipsByTrack
            .filter { !$0.value.isEmpty }
            .max { lhs, rhs in
                let left = covered(lhs.value)
                let right = covered(rhs.value)
                return left != right ? left < right : lhs.key.uuidString > rhs.key.uuidString
            }?
            .value ?? []
    }
}

/// Track-header clicks. A plain click selects one track, Shift adds every track up to the nearest
/// selected one, and Command adds or removes the clicked track.
enum TrackSelection {
    static func click(
        id: UUID,
        in selected: Set<UUID>,
        order: [UUID],
        modifiers: PointerModifiers
    ) -> Set<UUID> {
        if modifiers.command {
            var next = selected
            if next.contains(id) {
                next.remove(id)
            } else {
                next.insert(id)
            }
            return next
        }

        if modifiers.shift,
           let clicked = order.firstIndex(of: id),
           let nearest = selected.compactMap({ order.firstIndex(of: $0) }).min(by: { nearer($0, than: $1, to: clicked) }) {
            let span = order[min(clicked, nearest)...max(clicked, nearest)]
            return selected.union(span)
        }

        return [id]
    }

    private static func nearer(_ lhs: Int, than rhs: Int, to clicked: Int) -> Bool {
        let left = abs(lhs - clicked)
        let right = abs(rhs - clicked)
        return left != right ? left < right : lhs < rhs
    }
}

/// The clips picked for editing, on any number of tracks. Move, trim, split, join, duplicate,
/// and delete act on every selected clip at once.
struct ClipSelection: Equatable {
    private(set) var clipIDs: Set<UUID> = []

    init(_ clipIDs: some Sequence<UUID> = [UUID]()) {
        self.clipIDs = Set(clipIDs)
    }

    var isEmpty: Bool { clipIDs.isEmpty }

    func contains(_ clipID: UUID) -> Bool {
        clipIDs.contains(clipID)
    }

    mutating func select(_ ids: some Sequence<UUID>) {
        clipIDs.formUnion(ids)
    }

    mutating func deselectAll() {
        clipIDs.removeAll()
    }

    /// Drops clips that no longer exist.
    mutating func retain(existing clips: [TrackClip]) {
        clipIDs.formIntersection(clips.map(\.id))
    }

    /// Pointer-down on a clip. A plain press on an unselected clip selects only that clip; a press on
    /// a selected clip keeps the whole selection so a drag moves all of it. With `extending`, an
    /// unselected clip is added. Returns true when the clip was already selected under `extending`:
    /// the caller removes it if the pointer comes up without dragging.
    @discardableResult
    mutating func press(_ clipID: UUID, extending: Bool) -> Bool {
        if contains(clipID) {
            return extending
        }
        if extending {
            clipIDs.insert(clipID)
        } else {
            clipIDs = [clipID]
        }
        return false
    }

    /// Pointer-up without a drag. A plain click replaces the selection,
    /// including a click on a clip that was already part of it. Shift-click keeps what `press`
    /// wrote, and `removing` drops a clip that shift-click landed on when it was already selected.
    mutating func click(_ clipID: UUID, extending: Bool, removing: Bool) {
        if removing {
            clipIDs.remove(clipID)
            return
        }
        if !extending {
            clipIDs = [clipID]
        }
    }

    /// Clips on `trackIDs` that overlap the dragged time range. A point range selects nothing.
    /// `start` and `end` may arrive in either order.
    static func clipIDs(
        in clips: [TrackClip],
        trackIDs: Set<UUID>,
        from start: TimeInterval,
        to end: TimeInterval
    ) -> Set<UUID> {
        let lower = min(start, end)
        let upper = max(start, end)
        guard upper - lower > 0.000_1 else { return [] }
        return Set(
            clips
                .filter { trackIDs.contains($0.trackID) && $0.timelineStartSeconds < upper && $0.timelineEndSeconds > lower }
                .map(\.id)
        )
    }
}
