import Foundation

/// Ripple delete: removes a measure-aligned time span from the whole song and shifts
/// everything after it earlier to close the gap.
enum TimelineRippleStore {
    struct Track {
        let id: UUID
        let trimStart: TimeInterval
        let trimEnd: TimeInterval
        let sourceDuration: TimeInterval
    }

    struct Result {
        /// Tracks left with no clip regions (their content fell entirely inside the deleted span).
        var emptiedTrackIDs: [UUID]
    }

    /// Removes measures `[startMeasure, endMeasure)` and collapses the gap across every timeline dimension.
    @discardableResult
    static func rippleDeleteMeasures(
        startMeasure: Int,
        endMeasure: Int,
        markers: inout [ArrangementMarker],
        slots: inout [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: inout [ArrangementClipGap],
        clipRegions: inout [ClipRegion],
        loopSlotIDs: inout Set<UUID>,
        tempoChanges: inout [TempoChange],
        timeSignatureChanges: inout [TimeSignatureChange],
        midiEvents: inout [MIDIEvent],
        tracks: [Track],
        defaultBPM: Double,
        defaultNumerator: Int,
        defaultDenominator: Int
    ) -> Result {
        guard endMeasure > startMeasure, startMeasure >= 1 else {
            return Result(emptiedTrackIDs: [])
        }

        let originalTempo = tempoChanges
        let originalTimeSignature = timeSignatureChanges

        let tStart = MeasureTiming.timeAtStartOfMeasure(
            startMeasure,
            tempoChanges: originalTempo,
            timeSignatureChanges: originalTimeSignature
        )
        let tEnd = MeasureTiming.timeAtStartOfMeasure(
            endMeasure,
            tempoChanges: originalTempo,
            timeSignatureChanges: originalTimeSignature
        )
        let removedDuration = tEnd - tStart
        let removedMeasures = endMeasure - startMeasure
        guard removedDuration > 0 else { return Result(emptiedTrackIDs: []) }

        // 1. Materialize arrangement and source-track regions so every visible clip has explicit
        //    timeline bounds before we ripple-shift them.
        SongArrangementStore.materializeAllClipRegions(
            markers: markers,
            slots: slots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: &clipRegions,
            tracks: tracks.map { ($0.id, $0.trimStart, $0.trimEnd, $0.sourceDuration) }
        )
        clipGaps.removeAll()

        // 2. Ripple clip regions in timeline space (drop the window, shift later content left).
        clipRegions = clipRegions
            .flatMap { rippleRegion($0, tStart: tStart, tEnd: tEnd, removedDuration: removedDuration) }
            .sorted {
                if $0.timelineStartSeconds != $1.timelineStartSeconds {
                    return $0.timelineStartSeconds < $1.timelineStartSeconds
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        // 3. Shift section / arrangement markers (timeline == source here).
        let epsilon: TimeInterval = 0.001
        var removedMarkerIDs: Set<UUID> = []
        markers = markers.compactMap { marker in
            if marker.startSeconds <= tStart + epsilon {
                return marker
            }
            if marker.startSeconds < tEnd - epsilon {
                removedMarkerIDs.insert(marker.id)
                return nil
            }
            return ArrangementMarker(
                id: marker.id,
                name: marker.name,
                startSeconds: marker.startSeconds - removedDuration,
                sortOrder: marker.sortOrder
            )
        }

        // Drop slots (and loop references) whose marker was removed.
        let removedSlotIDs = Set(slots.filter { removedMarkerIDs.contains($0.markerID) }.map(\.id))
        slots.removeAll { removedMarkerIDs.contains($0.markerID) }
        loopSlotIDs.subtract(removedSlotIDs)

        // 4. Renumber tempo / time-signature changes in measure space.
        tempoChanges = rippledTempoChanges(
            originalTempo,
            startMeasure: startMeasure,
            endMeasure: endMeasure,
            removedMeasures: removedMeasures,
            defaultBPM: defaultBPM
        )
        timeSignatureChanges = rippledTimeSignatureChanges(
            originalTimeSignature,
            startMeasure: startMeasure,
            endMeasure: endMeasure,
            removedMeasures: removedMeasures,
            defaultNumerator: defaultNumerator,
            defaultDenominator: defaultDenominator
        )

        // 5. Shift MIDI events on the master timeline.
        midiEvents = midiEvents.compactMap { event in
            if event.timelineSeconds < tStart - epsilon {
                return event
            }
            if event.timelineSeconds < tEnd - epsilon {
                return nil
            }
            var shifted = event
            shifted.timelineSeconds -= removedDuration
            return shifted
        }

        let emptiedTrackIDs = tracks
            .map(\.id)
            .filter { id in !clipRegions.contains { $0.trackID == id } }

        return Result(emptiedTrackIDs: emptiedTrackIDs)
    }

    // MARK: - Clip regions

    private static func rippleRegion(
        _ region: ClipRegion,
        tStart: TimeInterval,
        tEnd: TimeInterval,
        removedDuration: TimeInterval
    ) -> [ClipRegion] {
        let minDuration = SongArrangementStore.minimumClipDuration
        let tolerance: TimeInterval = 0.000_1
        let start = region.timelineStartSeconds
        let end = region.timelineEndSeconds

        if end <= tStart + tolerance {
            return [region]
        }
        if start >= tEnd - tolerance {
            return [shifted(region, by: -removedDuration)]
        }
        if start >= tStart - tolerance, end <= tEnd + tolerance {
            return []
        }

        var pieces: [ClipRegion] = []
        let leftEnd = min(end, tStart)
        let hasLeft = start < tStart - tolerance && (leftEnd - start) >= minDuration
        if hasLeft {
            pieces.append(subRegion(region, fromTimeline: start, toTimeline: leftEnd, id: region.id))
        }

        let rightStart = max(start, tEnd)
        if end - rightStart >= minDuration {
            let rightID = hasLeft ? UUID() : region.id
            let right = subRegion(region, fromTimeline: rightStart, toTimeline: end, id: rightID)
            pieces.append(shifted(right, by: -removedDuration))
        }

        return pieces
    }

    private static func subRegion(
        _ region: ClipRegion,
        fromTimeline start: TimeInterval,
        toTimeline end: TimeInterval,
        id: UUID
    ) -> ClipRegion {
        let duration = region.timelineEndSeconds - region.timelineStartSeconds
        guard duration > 0 else { return region }

        let sourceDuration = region.sourceEndSeconds - region.sourceStartSeconds
        let startRatio = (start - region.timelineStartSeconds) / duration
        let endRatio = (end - region.timelineStartSeconds) / duration

        return ClipRegion(
            id: id,
            slotID: region.slotID,
            trackID: region.trackID,
            markerID: region.markerID,
            sourceStartSeconds: region.sourceStartSeconds + sourceDuration * startRatio,
            sourceEndSeconds: region.sourceStartSeconds + sourceDuration * endRatio,
            timelineStartSeconds: start,
            timelineEndSeconds: end
        )
    }

    private static func shifted(_ region: ClipRegion, by delta: TimeInterval) -> ClipRegion {
        ClipRegion(
            id: region.id,
            slotID: region.slotID,
            trackID: region.trackID,
            markerID: region.markerID,
            sourceStartSeconds: region.sourceStartSeconds,
            sourceEndSeconds: region.sourceEndSeconds,
            timelineStartSeconds: region.timelineStartSeconds + delta,
            timelineEndSeconds: region.timelineEndSeconds + delta
        )
    }

    // MARK: - Tempo / time signature

    private static func rippledTempoChanges(
        _ changes: [TempoChange],
        startMeasure: Int,
        endMeasure: Int,
        removedMeasures: Int,
        defaultBPM: Double
    ) -> [TempoChange] {
        var result = changes.filter { $0.startMeasure < startMeasure }

        // The measure that becomes the new `startMeasure` inherits the tempo active at `endMeasure`.
        if let boundary = changes.active(atMeasure: endMeasure) {
            let precedingBPM = result.active(atMeasure: startMeasure - 1)?.bpm
            if startMeasure == 1 || precedingBPM != boundary.bpm {
                result.append(TempoChange(id: boundary.id, startMeasure: startMeasure, bpm: boundary.bpm))
            }
        }

        for change in changes where change.startMeasure > endMeasure {
            result.append(
                TempoChange(
                    id: change.id,
                    startMeasure: change.startMeasure - removedMeasures,
                    bpm: change.bpm
                )
            )
        }

        return result.normalizedEnsuringInitialMarker(defaultBPM: defaultBPM)
    }

    private static func rippledTimeSignatureChanges(
        _ changes: [TimeSignatureChange],
        startMeasure: Int,
        endMeasure: Int,
        removedMeasures: Int,
        defaultNumerator: Int,
        defaultDenominator: Int
    ) -> [TimeSignatureChange] {
        var result = changes.filter { $0.startMeasure < startMeasure }

        if let boundary = changes.active(atMeasure: endMeasure) {
            let preceding = result.active(atMeasure: startMeasure - 1)
            let matchesPreceding = preceding?.numerator == boundary.numerator
                && preceding?.denominator == boundary.denominator
            if startMeasure == 1 || !matchesPreceding {
                result.append(
                    TimeSignatureChange(
                        id: boundary.id,
                        numerator: boundary.numerator,
                        denominator: boundary.denominator,
                        startMeasure: startMeasure
                    )
                )
            }
        }

        for change in changes where change.startMeasure > endMeasure {
            result.append(
                TimeSignatureChange(
                    id: change.id,
                    numerator: change.numerator,
                    denominator: change.denominator,
                    startMeasure: change.startMeasure - removedMeasures
                )
            )
        }

        return result.normalizedEnsuringInitialMarker(
            defaultNumerator: defaultNumerator,
            defaultDenominator: defaultDenominator
        )
    }
}
