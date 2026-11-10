import Foundation

/// Clip gain in decibels. The top three
/// quarters of the range cover −36…+36 evenly, and the bottom quarter compresses down to −144.
enum ClipGain {
    static let minimumDB = -144.0
    static let maximumDB = 36.0

    /// A value safe to store. Anything that is not a number stays at unity.
    static func stored(_ decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max(decibels, minimumDB), maximumDB)
    }

    /// Amplitude multiplier. −144 dB, and anything quieter, is silence.
    static func linearGain(decibels: Double) -> Float {
        let db = stored(decibels)
        guard db > minimumDB else { return 0 }
        return Float(pow(10, db / 20))
    }

    /// Fader position 0…1 for a stored gain. A value that is not a number sits at the bottom.
    static func position(forDecibels decibels: Double) -> Double {
        let db = decibels.isFinite ? min(max(decibels, minimumDB), maximumDB) : minimumDB
        if db >= -36 {
            return 0.25 + (db + 36) / 72 * 0.75
        }
        return (1 - pow((-36 - db) / 108, 1 / 1.5)) * 0.25
    }

    static func decibels(forPosition position: Double) -> Double {
        let p = position.isFinite ? min(max(position, 0), 1) : 0
        let db: Double
        if p >= 0.25 {
            db = -36 + (p - 0.25) / 0.75 * 72
        } else {
            db = -36 - pow(1 - p / 0.25, 1.5) * 108
        }
        return stored(db)
    }

    static func showsLine(decibels: Double) -> Bool {
        abs(decibels) > 0.01
    }

    /// Y inside the clip body. −36 dB sits at the bottom, +36 at the top.
    static func lineY(decibels: Double, bodyHeight: Double) -> Double {
        let db = min(max(decibels, -36), 36)
        return bodyHeight - 3 - ((db + 36) / 72) * (bodyHeight - 6)
    }

    static func readout(_ decibels: Double) -> String {
        String(format: "%+.1f", stored(decibels))
    }
}

/// Pure edits over `TrackClip`s and timeline markers.
///
/// Invariant kept by every function: on each track, clips are non-overlapping and at least
/// `TrackClip.minimumDuration` long. Clips that are placed (moved, pasted, duplicated) win over
/// whatever they land on; the existing clips are cut back around them.
enum ClipEditing {
    static let tolerance: TimeInterval = 0.000_1

    // MARK: - Overlap resolution

    /// Removes `[start, end)` from the given track's clips, splitting any clip that spans it.
    static func carve(
        trackID: UUID,
        from start: TimeInterval,
        to end: TimeInterval,
        excluding excludedIDs: Set<UUID> = [],
        in clips: inout [TrackClip]
    ) {
        guard end - start > tolerance else { return }
        clips = clips.flatMap { clip -> [TrackClip] in
            guard clip.trackID == trackID,
                  !excludedIDs.contains(clip.id),
                  clip.timelineStartSeconds < end - tolerance,
                  clip.timelineEndSeconds > start + tolerance else {
                return [clip]
            }

            var pieces: [TrackClip] = []
            if start - clip.timelineStartSeconds >= TrackClip.minimumDuration {
                pieces.append(subClip(clip, from: clip.timelineStartSeconds, to: start, id: clip.id))
            }
            if clip.timelineEndSeconds - end >= TrackClip.minimumDuration {
                let id = pieces.isEmpty ? clip.id : UUID()
                pieces.append(subClip(clip, from: end, to: clip.timelineEndSeconds, id: id))
            }
            return pieces
        }
    }

    /// Inserts or replaces `incoming`, cutting existing clips on the same tracks out of the way.
    static func place(_ incoming: [TrackClip], in clips: inout [TrackClip]) {
        let incomingIDs = Set(incoming.map(\.id))
        clips.removeAll { incomingIDs.contains($0.id) }

        // Incoming clips can land on the same track (moving clips from several tracks onto one);
        // the one that starts later wins where they overlap.
        var resolved: [TrackClip] = []
        for clip in incoming.sorted(by: { $0.timelineStartSeconds < $1.timelineStartSeconds }) {
            carve(
                trackID: clip.trackID,
                from: clip.timelineStartSeconds,
                to: clip.timelineEndSeconds,
                in: &resolved
            )
            resolved.append(clip)
        }

        for clip in resolved {
            carve(
                trackID: clip.trackID,
                from: clip.timelineStartSeconds,
                to: clip.timelineEndSeconds,
                in: &clips
            )
        }
        clips.append(contentsOf: resolved)
        sort(&clips)
    }

    static func sort(_ clips: inout [TrackClip]) {
        clips.sort {
            if $0.timelineStartSeconds != $1.timelineStartSeconds {
                return $0.timelineStartSeconds < $1.timelineStartSeconds
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    // MARK: - Single-clip edits

    /// Splits the clip at `time` and returns the new right-hand clip's ID.
    @discardableResult
    static func split(clipID: UUID, at time: TimeInterval, in clips: inout [TrackClip]) -> UUID? {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        let clip = clips[index]
        guard time - clip.timelineStartSeconds >= TrackClip.minimumDuration,
              clip.timelineEndSeconds - time >= TrackClip.minimumDuration else {
            return nil
        }

        let right = subClip(clip, from: time, to: clip.timelineEndSeconds, id: UUID())
        clips[index] = subClip(clip, from: clip.timelineStartSeconds, to: time, id: clip.id)
        clips.insert(right, at: index + 1)
        return right.id
    }

    enum Edge {
        case leading
        case trailing
    }

    /// The clip with one edge moved to `time`, clamped so it stays inside its audio file and keeps
    /// the minimum length. The edge stops at `blockers` (other clips being trimmed together on the
    /// same track); every other clip is overrun and cut back when the result is placed.
    static func trimmed(
        _ clip: TrackClip,
        edge: Edge,
        to time: TimeInterval,
        sourceDuration: TimeInterval,
        blockers: [TrackClip] = []
    ) -> TrackClip {
        let others = blockers.filter { $0.trackID == clip.trackID && $0.id != clip.id }
        var result = clip

        switch edge {
        case .leading:
            let previousEnd = others
                .filter { $0.timelineEndSeconds <= clip.timelineStartSeconds + tolerance }
                .map(\.timelineEndSeconds)
                .max() ?? 0
            let fileStart = clip.timelineStartSeconds - clip.sourceStartSeconds
            let minStart = max(previousEnd, fileStart, 0)
            let maxStart = clip.timelineEndSeconds - TrackClip.minimumDuration
            let newStart = min(max(time, minStart), maxStart)
            let delta = newStart - clip.timelineStartSeconds
            result.timelineStartSeconds = newStart
            result.sourceStartSeconds = clip.sourceStartSeconds + delta
            result.duration = clip.duration - delta
        case .trailing:
            let nextStart = others
                .filter { $0.timelineStartSeconds >= clip.timelineEndSeconds - tolerance }
                .map(\.timelineStartSeconds)
                .min() ?? .infinity
            // A track whose file length is unknown (missing audio) reports 0; don't clamp to it.
            let fileEnd = sourceDuration > 0
                ? clip.timelineStartSeconds + (sourceDuration - clip.sourceStartSeconds)
                : .infinity
            let minEnd = clip.timelineStartSeconds + TrackClip.minimumDuration
            let maxEnd = max(min(nextStart, fileEnd), minEnd)
            let newEnd = min(max(time, minEnd), maxEnd)
            result.duration = newEnd - clip.timelineStartSeconds
        }
        return result
    }

    /// Moves one edge of a clip. The clip wins over neighbours it is dragged across: they are
    /// shortened, split, or removed.
    @discardableResult
    static func trim(
        clipID: UUID,
        edge: Edge,
        to time: TimeInterval,
        sourceDuration: TimeInterval,
        in clips: inout [TrackClip]
    ) -> TrackClip? {
        guard let clip = clips.first(where: { $0.id == clipID }) else { return nil }
        let result = trimmed(clip, edge: edge, to: time, sourceDuration: sourceDuration)
        place([result], in: &clips)
        return result
    }

    /// Moves clips in time and optionally onto another track. The move is clamped so nothing
    /// starts before zero; whatever the moved clips land on is cut back.
    static func move(
        clipIDs: Set<UUID>,
        by delta: TimeInterval,
        toTrack targetTrackID: UUID? = nil,
        in clips: inout [TrackClip]
    ) {
        let selected = clips.filter { clipIDs.contains($0.id) }
        guard let earliest = selected.map(\.timelineStartSeconds).min() else { return }
        let clampedDelta = max(delta, -earliest)

        let moved = selected.map { clip in
            var copy = clip
            copy.timelineStartSeconds += clampedDelta
            if let targetTrackID {
                copy.trackID = targetTrackID
            }
            return copy
        }
        place(moved, in: &clips)
    }

    /// Joins a clip with the next clip on its track when both play one continuous stretch of the
    /// file, filling any gap between them. Returns the joined clip's ID.
    @discardableResult
    static func joinWithNext(clipID: UUID, in clips: inout [TrackClip]) -> UUID? {
        guard let clip = clips.first(where: { $0.id == clipID }),
              let next = clips
                .filter({ $0.trackID == clip.trackID && $0.timelineStartSeconds >= clip.timelineEndSeconds - tolerance })
                .min(by: { $0.timelineStartSeconds < $1.timelineStartSeconds }),
              abs(next.sourceOffset - clip.sourceOffset) <= tolerance,
              let index = clips.firstIndex(where: { $0.id == clipID }) else {
            return nil
        }

        clips[index].duration = next.timelineEndSeconds - clip.timelineStartSeconds
        clips.removeAll { $0.id == next.id }
        return clipID
    }

    static func delete(clipIDs: Set<UUID>, in clips: inout [TrackClip]) {
        clips.removeAll { clipIDs.contains($0.id) }
    }

    /// Sets one absolute gain, in decibels, on each clip. Clamped to −144…+36.
    static func setGain(clipIDs: Set<UUID>, decibels: Double, in clips: inout [TrackClip]) {
        let db = ClipGain.stored(decibels)
        for index in clips.indices where clipIDs.contains(clips[index].id) {
            clips[index].gainDB = db
        }
    }

    /// Adds `delta` decibels to each clip, clamped to the same ceiling and floor.
    static func nudgeGain(clipIDs: Set<UUID>, by delta: Double, in clips: inout [TrackClip]) {
        guard delta.isFinite else { return }
        for index in clips.indices where clipIDs.contains(clips[index].id) {
            clips[index].gainDB = ClipGain.stored(clips[index].gainDB + delta)
        }
    }

    // MARK: - Selection edits

    /// Copies the clips `delta` seconds later (earlier when negative) and returns the copies' IDs.
    /// The copies win over whatever they land on, including the originals.
    @discardableResult
    static func copy(clipIDs: Set<UUID>, by delta: TimeInterval, in clips: inout [TrackClip]) -> Set<UUID> {
        let selected = clips.filter { clipIDs.contains($0.id) }
        guard let earliest = selected.map(\.timelineStartSeconds).min() else { return [] }
        let clampedDelta = max(delta, -earliest)
        let copies = selected.map { clip in
            TrackClip(
                trackID: clip.trackID,
                timelineStartSeconds: clip.timelineStartSeconds + clampedDelta,
                duration: clip.duration,
                sourceStartSeconds: clip.sourceStartSeconds,
                gainDB: clip.gainDB
            )
        }
        place(copies, in: &clips)
        return Set(copies.map(\.id))
    }

    /// Copies the clips to just after the span they cover and returns the copies' IDs.
    @discardableResult
    static func duplicate(clipIDs: Set<UUID>, in clips: inout [TrackClip]) -> Set<UUID> {
        let selected = clips.filter { clipIDs.contains($0.id) }
        guard let start = selected.map(\.timelineStartSeconds).min(),
              let end = selected.map(\.timelineEndSeconds).max() else {
            return []
        }
        return copy(clipIDs: clipIDs, by: end - start, in: &clips)
    }

    /// Moves the same edge of every listed clip by `delta`; each clip is clamped on its own. A listed
    /// clip's edge stops at the next listed clip on its track; unlisted clips are overrun and cut back.
    static func trim(
        clipIDs: Set<UUID>,
        edge: Edge,
        by delta: TimeInterval,
        sourceDuration: (_ trackID: UUID) -> TimeInterval,
        in clips: inout [TrackClip]
    ) {
        let listed = clips.filter { clipIDs.contains($0.id) }
        let results = listed.map { clip in
            let edgeTime = edge == .leading ? clip.timelineStartSeconds : clip.timelineEndSeconds
            return trimmed(
                clip,
                edge: edge,
                to: edgeTime + delta,
                sourceDuration: sourceDuration(clip.trackID),
                blockers: listed
            )
        }
        place(results, in: &clips)
    }

    /// Splits every listed clip that spans `time` and returns the new right-hand clips' IDs.
    @discardableResult
    static func split(clipIDs: Set<UUID>, at time: TimeInterval, in clips: inout [TrackClip]) -> Set<UUID> {
        var rightIDs: Set<UUID> = []
        for id in clipIDs {
            if let rightID = split(clipID: id, at: time, in: &clips) {
                rightIDs.insert(rightID)
            }
        }
        return rightIDs
    }

    /// Splits at each edit-selection time, earliest first.
    /// A piece made by an earlier cut is split again when a later time falls inside it,
    /// so a range's start and end leave the selection as its own clip. Returns every new right-hand clip.
    @discardableResult
    static func split(clipIDs: Set<UUID>, at times: [TimeInterval], in clips: inout [TrackClip]) -> Set<UUID> {
        var pool = clipIDs
        var created: Set<UUID> = []
        var last: TimeInterval?
        for time in times.sorted() {
            if let last, abs(time - last) <= tolerance { continue }
            last = time
            let rightIDs = split(clipIDs: pool, at: time, in: &clips)
            pool.formUnion(rightIDs)
            created.formUnion(rightIDs)
        }
        return created
    }

    /// Joins selected clips that sit next to each other on a track. A track with only one selected
    /// clip joins it with the clip after it. Returns the IDs of the listed clips that remain.
    @discardableResult
    static func join(clipIDs: Set<UUID>, in clips: inout [TrackClip]) -> Set<UUID> {
        let selectedByTrack = Dictionary(grouping: clips.filter { clipIDs.contains($0.id) }, by: \.trackID)
        for (trackID, selected) in selectedByTrack {
            let ordered = selected.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
            guard ordered.count > 1 else {
                joinWithNext(clipID: ordered[0].id, in: &clips)
                continue
            }
            for index in stride(from: ordered.count - 2, through: 0, by: -1) {
                let next = clips
                    .filter { $0.trackID == trackID && $0.timelineStartSeconds >= ordered[index].timelineEndSeconds - tolerance }
                    .min { $0.timelineStartSeconds < $1.timelineStartSeconds }
                guard next?.id == ordered[index + 1].id else { continue }
                joinWithNext(clipID: ordered[index].id, in: &clips)
            }
        }
        return clipIDs.intersection(clips.map(\.id))
    }

    /// Clears `[start, end)` on the given tracks without shifting anything.
    static func deleteRange(
        trackIDs: Set<UUID>,
        from start: TimeInterval,
        to end: TimeInterval,
        in clips: inout [TrackClip]
    ) {
        for trackID in trackIDs {
            carve(trackID: trackID, from: start, to: end, in: &clips)
        }
    }

    // MARK: - Whole-song range edits
    //
    // These move clips, markers, and MIDI together. Tempo and time-signature changes are anchored
    // to measures, so callers shift those separately.

    /// Splits every clip that spans `time`. When one side of the cut would be shorter than
    /// `TrackClip.minimumDuration`, that sliver is dropped instead, so no clip is left straddling `time`.
    static func splitAll(at time: TimeInterval, in clips: inout [TrackClip]) {
        let spanning = clips.filter {
            $0.timelineStartSeconds < time - tolerance && $0.timelineEndSeconds > time + tolerance
        }
        for clip in spanning {
            if split(clipID: clip.id, at: time, in: &clips) != nil { continue }
            if time - clip.timelineStartSeconds < TrackClip.minimumDuration {
                carve(trackID: clip.trackID, from: clip.timelineStartSeconds, to: time, in: &clips)
            } else {
                carve(trackID: clip.trackID, from: time, to: clip.timelineEndSeconds, in: &clips)
            }
        }
    }

    /// Removes `[start, end)` from every track and closes the gap. When the section that owns the
    /// audio right after the range started inside it, that marker moves to `start` so the
    /// remaining audio keeps its name.
    static func rippleDelete(
        from start: TimeInterval,
        to end: TimeInterval,
        timeline: inout SongTimeline,
        midiEvents: inout [MIDIEvent]
    ) {
        let length = end - start
        guard length > tolerance else { return }

        let materialFollows = timeline.clips.contains { $0.timelineEndSeconds > end + tolerance }
            || timeline.markers.contains { $0.startSeconds > end + tolerance }
        let trackIDs = Set(timeline.clips.map(\.trackID))
        deleteRange(trackIDs: trackIDs, from: start, to: end, in: &timeline.clips)
        for index in timeline.clips.indices where timeline.clips[index].timelineStartSeconds >= end - tolerance {
            timeline.clips[index].timelineStartSeconds -= length
        }
        sort(&timeline.clips)

        let owner = timeline.sortedMarkers.last { $0.startSeconds <= end + tolerance }
        let hasMarkerAtEnd = timeline.markers.contains { abs($0.startSeconds - end) <= tolerance }
        timeline.markers = timeline.markers.compactMap { marker in
            if marker.startSeconds < start - tolerance {
                return marker
            }
            var shifted = marker
            if marker.startSeconds >= end - tolerance {
                shifted.startSeconds -= length
                return shifted
            }
            guard marker.id == owner?.id, !hasMarkerAtEnd, materialFollows else { return nil }
            shifted.startSeconds = start
            return shifted
        }

        midiEvents = midiEvents.compactMap { event in
            if event.timelineSeconds < start - tolerance { return event }
            if event.timelineSeconds < end - tolerance { return nil }
            var shifted = event
            shifted.timelineSeconds -= length
            return shifted
        }
    }

    /// Opens `length` seconds of silence at `position` on every track.
    static func insertSpace(
        at position: TimeInterval,
        length: TimeInterval,
        timeline: inout SongTimeline,
        midiEvents: inout [MIDIEvent]
    ) {
        guard length > tolerance else { return }

        splitAll(at: position, in: &timeline.clips)
        for index in timeline.clips.indices where timeline.clips[index].timelineStartSeconds >= position - tolerance {
            timeline.clips[index].timelineStartSeconds += length
        }
        sort(&timeline.clips)

        for index in timeline.markers.indices where timeline.markers[index].startSeconds >= position - tolerance {
            timeline.markers[index].startSeconds += length
        }
        for index in midiEvents.indices where midiEvents[index].timelineSeconds >= position - tolerance {
            midiEvents[index].timelineSeconds += length
        }
    }

    /// Copies `[start, end)` on every track and inserts it at `destination`, pushing later material
    /// right. The copy is named after the section it came from, and material after the insertion
    /// point keeps its section name. Returns the IDs of the copied markers, keyed by the original
    /// marker IDs.
    @discardableResult
    static func duplicateRange(
        from start: TimeInterval,
        to end: TimeInterval,
        insertingAt destination: TimeInterval,
        copyLoops: Bool = false,
        timeline: inout SongTimeline,
        midiEvents: inout [MIDIEvent]
    ) -> [UUID: UUID] {
        let length = end - start
        guard length > tolerance else { return [:] }

        let copiedClips = timeline.clips.compactMap { clip -> TrackClip? in
            let from = max(clip.timelineStartSeconds, start)
            let to = min(clip.timelineEndSeconds, end)
            guard to - from >= TrackClip.minimumDuration else { return nil }
            var copy = subClip(clip, from: from, to: to, id: UUID())
            copy.timelineStartSeconds = destination + (from - start)
            return copy
        }

        let sorted = timeline.sortedMarkers
        var markerIDMap: [UUID: UUID] = [:]
        var copiedMarkers = sorted
            .filter { $0.startSeconds >= start - tolerance && $0.startSeconds < end - tolerance }
            .map { marker -> ArrangementMarker in
                let copy = ArrangementMarker(
                    name: marker.name,
                    startSeconds: destination + max(0, marker.startSeconds - start),
                    loops: copyLoops && marker.loops
                )
                markerIDMap[marker.id] = copy.id
                return copy
            }
        let copyStartsOnMarker = sorted.contains { abs($0.startSeconds - start) <= tolerance }
        if !copyStartsOnMarker, let owner = sorted.last(where: { $0.startSeconds < start }) {
            copiedMarkers.append(
                ArrangementMarker(name: owner.name, startSeconds: destination, loops: copyLoops && owner.loops)
            )
        }

        let destinationOwner = sorted.last { $0.startSeconds < destination - tolerance }
        let destinationOnMarker = sorted.contains { abs($0.startSeconds - destination) <= tolerance }
        let materialFollows = timeline.clips.contains { $0.timelineEndSeconds > destination + tolerance }
            || sorted.contains { $0.startSeconds > destination + tolerance }

        let copiedMIDI = midiEvents
            .filter { $0.timelineSeconds >= start - tolerance && $0.timelineSeconds < end - tolerance }
            .map { event in
                MIDIEvent(
                    trackID: event.trackID,
                    timelineSeconds: destination + (event.timelineSeconds - start),
                    commandID: event.commandID,
                    label: event.label
                )
            }

        insertSpace(at: destination, length: length, timeline: &timeline, midiEvents: &midiEvents)

        timeline.clips.append(contentsOf: copiedClips)
        sort(&timeline.clips)
        timeline.markers.append(contentsOf: copiedMarkers)
        if let destinationOwner, !destinationOnMarker, materialFollows {
            timeline.markers.append(
                ArrangementMarker(
                    name: destinationOwner.name,
                    startSeconds: destination + length,
                    loops: destinationOwner.loops
                )
            )
        }
        timeline.markers.sort { $0.startSeconds < $1.startSeconds }
        midiEvents.append(contentsOf: copiedMIDI)
        return markerIDMap
    }

    /// Moves `[start, end)` on every track to `destination`, which is measured on the timeline
    /// before the move. Moved markers keep their IDs and loop flags.
    static func moveRange(
        from start: TimeInterval,
        to end: TimeInterval,
        insertingAt destination: TimeInterval,
        timeline: inout SongTimeline,
        midiEvents: inout [MIDIEvent]
    ) {
        let length = end - start
        guard length > tolerance,
              destination <= start + tolerance || destination >= end - tolerance,
              abs(destination - start) > tolerance,
              abs(destination - end) > tolerance else {
            return
        }

        let originals = Dictionary(uniqueKeysWithValues: timeline.markers.map { ($0.id, $0) })
        let copies = duplicateRange(
            from: start,
            to: end,
            insertingAt: destination,
            timeline: &timeline,
            midiEvents: &midiEvents
        )

        let originalStart = destination <= start ? start + length : start
        rippleDelete(
            from: originalStart,
            to: originalStart + length,
            timeline: &timeline,
            midiEvents: &midiEvents
        )

        let originalIDsByCopy = Dictionary(uniqueKeysWithValues: copies.map { ($1, $0) })
        timeline.markers.removeAll { copies[$0.id] != nil }
        timeline.markers = timeline.markers.map { marker in
            guard let originalID = originalIDsByCopy[marker.id],
                  var restored = originals[originalID] else {
                return marker
            }
            restored.startSeconds = marker.startSeconds
            return restored
        }
    }

    // MARK: - Section edits

    static func duplicateSection(
        _ sectionID: UUID,
        timeline: inout SongTimeline,
        midiEvents: inout [MIDIEvent]
    ) {
        guard let section = timeline.sections().first(where: { $0.id == sectionID }) else { return }
        duplicateRange(
            from: section.timelineStartSeconds,
            to: section.timelineEndSeconds,
            insertingAt: section.timelineEndSeconds,
            timeline: &timeline,
            midiEvents: &midiEvents
        )
    }

    static func removeSection(
        _ sectionID: UUID,
        timeline: inout SongTimeline,
        midiEvents: inout [MIDIEvent]
    ) {
        guard let section = timeline.sections().first(where: { $0.id == sectionID }) else { return }
        rippleDelete(from: section.timelineStartSeconds, to: section.timelineEndSeconds, timeline: &timeline, midiEvents: &midiEvents)
    }

    /// Moves a section so it sits at `index` in the section order (the position it would have in
    /// the list before the move, as `Array.move(fromOffsets:toOffset:)` uses).
    static func moveSection(
        _ sectionID: UUID,
        toIndex index: Int,
        timeline: inout SongTimeline,
        midiEvents: inout [MIDIEvent]
    ) {
        let sections = timeline.sections()
        guard let section = sections.first(where: { $0.id == sectionID }) else { return }
        let destination = index < sections.count ? sections[max(0, index)].timelineStartSeconds
            : (sections.last?.timelineEndSeconds ?? 0)
        moveRange(
            from: section.timelineStartSeconds,
            to: section.timelineEndSeconds,
            insertingAt: destination,
            timeline: &timeline,
            midiEvents: &midiEvents
        )
    }

    // MARK: - Helpers

    private static func subClip(
        _ clip: TrackClip,
        from start: TimeInterval,
        to end: TimeInterval,
        id: UUID
    ) -> TrackClip {
        TrackClip(
            id: id,
            trackID: clip.trackID,
            timelineStartSeconds: start,
            duration: end - start,
            sourceStartSeconds: clip.sourceTime(atTimeline: start),
            gainDB: clip.gainDB
        )
    }
}
