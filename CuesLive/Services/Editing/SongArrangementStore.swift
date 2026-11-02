import Foundation

enum SongArrangementStore {
    static let minimumClipDuration: TimeInterval = 0.1

    static func normalized(_ arrangement: SongArrangement, markers: [ArrangementMarker]) -> SongArrangement {
        validated(arrangement, markers: markers)
    }

    static func defaultArrangement(for markers: [ArrangementMarker]) -> SongArrangement {
        SongArrangement(
            slots: defaultSlots(from: markers),
            clipTrims: [],
            removedClips: [],
            clipGaps: [],
            clipRegions: []
        )
    }

    static func makeLayoutInputs(
        markers: [ArrangementMarker],
        trackIDs: [UUID],
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> ArrangementLayoutInputs {
        let sortedMarkers = markers.sortedByTime
        return ArrangementLayoutInputs(
            sortedMarkers: sortedMarkers,
            markersByID: Dictionary(uniqueKeysWithValues: sortedMarkers.map { ($0.id, $0) }),
            trackIDs: trackIDs,
            sourceDurationForTrack: sourceDurationForTrack
        )
    }

    /// True when slots match markers in source order with no arrangement-slot edits.
    /// Identity arrangements keep continuous track clips; section markers still appear on the ruler.
    /// After arrangement changes, tracks use a packed layout but only cut where source continuity
    /// breaks (moved / duplicated / removed sections), not at every section boundary.
    static func usesSectionedTrackLayout(
        slots: [ArrangementSlot],
        markers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim] = [],
        removedClips: [ArrangementRemovedClip] = [],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = []
    ) -> Bool {
        guard isIdentitySlotSequence(slots, markers: markers) else { return true }

        let slotIDs = Set(slots.map(\.id))
        if clipTrims.contains(where: { slotIDs.contains($0.slotID) }) { return true }
        if removedClips.contains(where: { slotIDs.contains($0.slotID) }) { return true }
        if clipGaps.contains(where: { slotIDs.contains($0.slotID) }) { return true }
        if clipRegions.contains(where: { slotIDs.contains($0.slotID) }) { return true }
        return false
    }

    static func isIdentitySlotSequence(
        _ slots: [ArrangementSlot],
        markers: [ArrangementMarker]
    ) -> Bool {
        let sortedMarkers = markers.sortedByTime
        guard slots.count == sortedMarkers.count else { return false }
        return zip(slots, sortedMarkers).allSatisfy { $0.markerID == $1.id }
    }

    static func buildLayoutSnapshot(
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = [],
        inputs: ArrangementLayoutInputs
    ) -> ArrangementLayoutSnapshot {
        let sectioned = usesSectionedTrackLayout(
            slots: slots,
            markers: inputs.sortedMarkers,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions
        )
        let rulerSections: [ArrangementDisplaySection]
        let trackSections: [UUID: [ArrangementDisplaySection]]

        if sectioned {
            let columns = arrangementColumns(slots: slots, inputs: inputs)
            rulerSections = rulerDisplaySections(columns: columns, inputs: inputs)
            trackSections = Dictionary(
                uniqueKeysWithValues: inputs.trackIDs.map { trackID in
                    (
                        trackID,
                        trackDisplaySections(
                            for: trackID,
                            clipTrims: clipTrims,
                            removedClips: removedClips,
                            clipGaps: clipGaps,
                            clipRegions: clipRegions,
                            columns: columns,
                            inputs: inputs
                        )
                    )
                }
            )
        } else {
            // Keep section labels on the ruler at absolute source times; leave tracks uncut.
            rulerSections = sourceAlignedRulerSections(slots: slots, inputs: inputs)
            trackSections = Dictionary(
                uniqueKeysWithValues: inputs.trackIDs.map { ($0, []) }
            )
        }

        return alignedLayoutSnapshot(
            rulerSections: rulerSections,
            trackSections: trackSections
        )
    }

    /// Sections that drive audio playback, honoring per-slot clip regions.
    static func playbackTrackSections(
        for trackID: UUID,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = [],
        inputs: ArrangementLayoutInputs
    ) -> [ArrangementDisplaySection] {
        let sections = trackDisplaySections(
            for: trackID,
            slots: slots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            inputs: inputs
        )
        if !sections.isEmpty {
            return sections
        }

        return sourceTrackDisplaySections(
            trackID: trackID,
            trimStart: trimStart,
            trimEnd: trimEnd,
            clipGaps: clipGaps,
            clipRegions: clipRegions
        )
    }

    static func playbackLayoutSnapshot(
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = [],
        tracks: [(id: UUID, trimStart: TimeInterval, trimEnd: TimeInterval)],
        inputs: ArrangementLayoutInputs
    ) -> ArrangementLayoutSnapshot {
        let sectioned = usesSectionedTrackLayout(
            slots: slots,
            markers: inputs.sortedMarkers,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions
        )
        let rulerSections: [ArrangementDisplaySection]
        let displaySectionsByTrack: [UUID: [ArrangementDisplaySection]]

        if sectioned {
            let columns = arrangementColumns(slots: slots, inputs: inputs)
            rulerSections = rulerDisplaySections(columns: columns, inputs: inputs)
            displaySectionsByTrack = Dictionary(
                uniqueKeysWithValues: inputs.trackIDs.map { trackID in
                    (
                        trackID,
                        trackDisplaySections(
                            for: trackID,
                            clipTrims: clipTrims,
                            removedClips: removedClips,
                            clipGaps: clipGaps,
                            clipRegions: clipRegions,
                            columns: columns,
                            inputs: inputs
                        )
                    )
                }
            )
        } else {
            rulerSections = sourceAlignedRulerSections(slots: slots, inputs: inputs)
            displaySectionsByTrack = Dictionary(
                uniqueKeysWithValues: inputs.trackIDs.map { ($0, []) }
            )
        }

        let sectionsByTrack = Dictionary(
            uniqueKeysWithValues: tracks.map { track in
                let sections = displaySectionsByTrack[track.id] ?? []
                if !sections.isEmpty {
                    return (track.id, sections)
                }
                return (
                    track.id,
                    sourceTrackDisplaySections(
                        trackID: track.id,
                        trimStart: track.trimStart,
                        trimEnd: track.trimEnd,
                        clipGaps: clipGaps,
                        clipRegions: clipRegions
                    )
                )
            }
        )
        return alignedLayoutSnapshot(
            rulerSections: rulerSections,
            trackSections: sectionsByTrack
        )
    }

    static func segmentID(slotID: UUID, index: Int) -> UUID {
        var bytes = slotID.uuid
        bytes.14 = UInt8((index >> 8) & 0xFF)
        bytes.15 = UInt8(index & 0xFF)
        return UUID(uuid: bytes)
    }

    static func gaps(
        slotID: UUID,
        trackID: UUID,
        in clipGaps: [ArrangementClipGap]
    ) -> [ArrangementClipGap] {
        clipGaps
            .filter { $0.slotID == slotID && $0.trackID == trackID }
            .sorted { $0.sourceStartSeconds < $1.sourceStartSeconds }
    }

    static func sourceSegments(
        from sourceStart: TimeInterval,
        to sourceEnd: TimeInterval,
        excluding gaps: [ArrangementClipGap]
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        var segments: [(start: TimeInterval, end: TimeInterval)] = [(sourceStart, sourceEnd)]

        for gap in gaps.sorted(by: { $0.sourceStartSeconds < $1.sourceStartSeconds }) {
            segments = segments.flatMap { segment -> [(TimeInterval, TimeInterval)] in
                if gap.sourceEndSeconds <= segment.start + 0.000_1
                    || gap.sourceStartSeconds >= segment.end - 0.000_1 {
                    return [segment]
                }

                var split: [(TimeInterval, TimeInterval)] = []
                if gap.sourceStartSeconds > segment.start + 0.000_1 {
                    split.append((segment.start, gap.sourceStartSeconds))
                }
                if gap.sourceEndSeconds < segment.end - 0.000_1 {
                    split.append((gap.sourceEndSeconds, segment.end))
                }
                return split
            }
        }

        return segments.filter { $0.end - $0.start >= minimumClipDuration }
    }

    static func addGap(
        slotID: UUID,
        trackID: UUID,
        sourceStart: TimeInterval,
        sourceEnd: TimeInterval,
        in clipGaps: inout [ArrangementClipGap]
    ) {
        guard sourceEnd - sourceStart >= minimumClipDuration else { return }

        var merged = gaps(slotID: slotID, trackID: trackID, in: clipGaps)
        merged.append(
            ArrangementClipGap(
                slotID: slotID,
                trackID: trackID,
                sourceStartSeconds: sourceStart,
                sourceEndSeconds: sourceEnd
            )
        )
        merged.sort { $0.sourceStartSeconds < $1.sourceStartSeconds }

        var combined: [ArrangementClipGap] = []
        for gap in merged {
            guard let last = combined.last else {
                combined.append(gap)
                continue
            }
            if gap.sourceStartSeconds <= last.sourceEndSeconds + 0.000_1 {
                combined[combined.count - 1] = ArrangementClipGap(
                    slotID: slotID,
                    trackID: trackID,
                    sourceStartSeconds: last.sourceStartSeconds,
                    sourceEndSeconds: max(last.sourceEndSeconds, gap.sourceEndSeconds)
                )
            } else {
                combined.append(gap)
            }
        }

        clipGaps.removeAll { $0.slotID == slotID && $0.trackID == trackID }
        clipGaps.append(contentsOf: combined)
    }

    static func sourceRange(
        forTimelineRange range: ClosedRange<TimeInterval>,
        slotID: UUID,
        sections: [ArrangementDisplaySection]
    ) -> (start: TimeInterval, end: TimeInterval)? {
        let slotSections = sections
            .filter { $0.slotID == slotID }
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }

        var sourceStarts: [TimeInterval] = []
        var sourceEnds: [TimeInterval] = []

        for section in slotSections {
            let overlapStart = max(range.lowerBound, section.timelineStartSeconds)
            let overlapEnd = min(range.upperBound, section.timelineEndSeconds)
            guard overlapEnd - overlapStart >= minimumClipDuration else { continue }

            let offsetStart = overlapStart - section.timelineStartSeconds
            let offsetEnd = overlapEnd - section.timelineStartSeconds
            sourceStarts.append(section.sourceStartSeconds + offsetStart)
            sourceEnds.append(section.sourceStartSeconds + offsetEnd)
        }

        guard let start = sourceStarts.min(), let end = sourceEnds.max(), end - start >= minimumClipDuration else {
            return nil
        }
        return (start, end)
    }

    /// Builds timeline sections for a source-only track, preserving absolute timeline
    /// positions so deleted regions leave blank space instead of rippling later clips.
    static func sourceTrackDisplaySections(
        trackID: UUID,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = []
    ) -> [ArrangementDisplaySection] {
        let stored = ClipRegionStore.regions(forTrack: trackID, in: clipRegions)
        if !stored.isEmpty {
            return stored.map {
                ClipRegionStore.displaySection(
                    from: $0,
                    name: "",
                    columnStart: trimStart,
                    columnEnd: trimEnd
                )
            }
        }

        let trackGaps = gaps(slotID: trackID, trackID: trackID, in: clipGaps)
        let segments = sourceSegments(from: trimStart, to: trimEnd, excluding: trackGaps)
        guard !segments.isEmpty else { return [] }

        return segments.enumerated().map { index, segment in
            let sectionID = segments.count == 1 ? trackID : segmentID(slotID: trackID, index: index)
            return ArrangementDisplaySection(
                id: sectionID,
                slotID: trackID,
                markerID: trackID,
                name: "",
                sourceStartSeconds: segment.start,
                sourceEndSeconds: segment.end,
                timelineStartSeconds: segment.start,
                timelineEndSeconds: segment.end,
                columnStartSeconds: trimStart,
                columnEndSeconds: trimEnd
            )
        }
    }

    static func defaultSlots(from markers: [ArrangementMarker]) -> [ArrangementSlot] {
        markers.sortedByTime.map { ArrangementSlot(markerID: $0.id) }
    }

    static func markerSourceRange(
        for marker: ArrangementMarker,
        markers: [ArrangementMarker],
        sourceDuration: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval) {
        markerSourceRange(for: marker, sortedMarkers: markers.sortedByTime, sourceDuration: sourceDuration)
    }

    private static func markerSourceRange(
        for marker: ArrangementMarker,
        sortedMarkers: [ArrangementMarker],
        sourceDuration: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval) {
        let safeSourceDuration = max(sourceDuration, 0.001)
        guard let index = sortedMarkers.firstIndex(where: { $0.id == marker.id }) else {
            return (marker.startSeconds, safeSourceDuration)
        }
        let end: TimeInterval
        if index + 1 < sortedMarkers.count {
            end = sortedMarkers[index + 1].startSeconds
        } else {
            end = safeSourceDuration
        }
        return (marker.startSeconds, end)
    }

    static func trims(
        slotID: UUID,
        trackID: UUID,
        in clipTrims: [ArrangementClipTrim]
    ) -> (leading: TimeInterval, trailing: TimeInterval) {
        guard let match = clipTrims.first(where: { $0.slotID == slotID && $0.trackID == trackID }) else {
            return (0, 0)
        }
        return (match.leadingTrim, match.trailingTrim)
    }

    static func isClipRemoved(
        slotID: UUID,
        trackID: UUID,
        in removedClips: [ArrangementRemovedClip]
    ) -> Bool {
        removedClips.contains { $0.slotID == slotID && $0.trackID == trackID }
    }

    static func removeClip(
        slotID: UUID,
        trackID: UUID,
        clipTrims: inout [ArrangementClipTrim],
        removedClips: inout [ArrangementRemovedClip],
        clipGaps: inout [ArrangementClipGap],
        clipRegions: inout [ClipRegion]
    ) {
        let removed = ArrangementRemovedClip(slotID: slotID, trackID: trackID)
        if !removedClips.contains(removed) {
            removedClips.append(removed)
        }
        clipTrims.removeAll { $0.slotID == slotID && $0.trackID == trackID }
        clipGaps.removeAll { $0.slotID == slotID && $0.trackID == trackID }
        ClipRegionStore.removeAllRegions(slotID: slotID, trackID: trackID, in: &clipRegions)
    }

    static func ensureClipRegions(
        slotID: UUID,
        trackID: UUID,
        markerID: UUID,
        sourceRange: (start: TimeInterval, end: TimeInterval),
        boundsStart: TimeInterval,
        columnStart: TimeInterval,
        clipGaps: [ArrangementClipGap],
        clipRegions: inout [ClipRegion]
    ) {
        guard !ClipRegionStore.hasStoredRegions(slotID: slotID, trackID: trackID, in: clipRegions) else {
            return
        }
        clipRegions.append(
            contentsOf: ClipRegionStore.defaultRegions(
                slotID: slotID,
                trackID: trackID,
                markerID: markerID,
                sourceRange: sourceRange,
                boundsStart: boundsStart,
                columnStart: columnStart,
                gaps: clipGaps
            )
        )
    }

    static func ensureSourceTrackRegions(
        trackID: UUID,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        clipGaps: [ArrangementClipGap],
        clipRegions: inout [ClipRegion]
    ) {
        guard !ClipRegionStore.hasStoredRegions(slotID: trackID, trackID: trackID, in: clipRegions) else {
            return
        }
        clipRegions.append(
            contentsOf: ClipRegionStore.defaultSourceTrackRegions(
                trackID: trackID,
                trimStart: trimStart,
                trimEnd: trimEnd,
                gaps: clipGaps
            )
        )
    }

    /// Materializes arrangement slot regions and source-track fallback regions so timeline edits
    /// can be applied to explicit clip bounds before ripple/shift operations.
    static func materializeAllClipRegions(
        markers: [ArrangementMarker],
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap],
        clipRegions: inout [ClipRegion],
        tracks: [(id: UUID, trimStart: TimeInterval, trimEnd: TimeInterval, sourceDuration: TimeInterval)]
    ) {
        let trackIDs = tracks.map(\.id)
        let inputs = makeLayoutInputs(
            markers: markers,
            trackIDs: trackIDs,
            sourceDurationForTrack: { trackID in
                tracks.first(where: { $0.id == trackID })?.sourceDuration ?? 0
            }
        )
        let columns = arrangementColumns(slots: slots, inputs: inputs)

        for column in columns {
            for trackID in trackIDs {
                if isClipRemoved(slotID: column.slot.id, trackID: trackID, in: removedClips) {
                    continue
                }

                let sourceDuration = inputs.sourceDurationForTrack(trackID)
                guard let sourceRange = trimmedSourceRange(
                    slot: column.slot,
                    trackID: trackID,
                    marker: column.marker,
                    sortedMarkers: inputs.sortedMarkers,
                    clipTrims: clipTrims,
                    sourceDuration: sourceDuration
                ) else {
                    continue
                }

                let bounds = markerSourceRange(
                    for: column.marker,
                    sortedMarkers: inputs.sortedMarkers,
                    sourceDuration: sourceDuration
                )
                ensureClipRegions(
                    slotID: column.slot.id,
                    trackID: trackID,
                    markerID: column.marker.id,
                    sourceRange: sourceRange,
                    boundsStart: bounds.start,
                    columnStart: column.columnStart,
                    clipGaps: clipGaps,
                    clipRegions: &clipRegions
                )
            }
        }

        for track in tracks where !clipRegions.contains(where: { $0.trackID == track.id }) {
            ensureSourceTrackRegions(
                trackID: track.id,
                trimStart: track.trimStart,
                trimEnd: track.trimEnd,
                clipGaps: clipGaps,
                clipRegions: &clipRegions
            )
        }
    }

    static func migrateClipGapsToRegions(
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        clipGaps: [ArrangementClipGap],
        removedClips: [ArrangementRemovedClip],
        inputs: ArrangementLayoutInputs,
        sourceTracks: [(trackID: UUID, trimStart: TimeInterval, trimEnd: TimeInterval)]
    ) -> [ClipRegion] {
        var regions: [ClipRegion] = []
        let columns = arrangementColumns(slots: slots, inputs: inputs)

        for column in columns {
            for trackID in inputs.trackIDs {
                guard !isClipRemoved(slotID: column.slot.id, trackID: trackID, in: removedClips) else {
                    continue
                }
                let sourceDuration = inputs.sourceDurationForTrack(trackID)
                guard let sourceRange = trimmedSourceRange(
                    slot: column.slot,
                    trackID: trackID,
                    marker: column.marker,
                    sortedMarkers: inputs.sortedMarkers,
                    clipTrims: clipTrims,
                    sourceDuration: sourceDuration
                ) else { continue }

                let bounds = markerSourceRange(
                    for: column.marker,
                    sortedMarkers: inputs.sortedMarkers,
                    sourceDuration: sourceDuration
                )
                let slotGaps = gaps(slotID: column.slot.id, trackID: trackID, in: clipGaps)
                guard !slotGaps.isEmpty else { continue }

                regions.append(
                    contentsOf: ClipRegionStore.defaultRegions(
                        slotID: column.slot.id,
                        trackID: trackID,
                        markerID: column.marker.id,
                        sourceRange: sourceRange,
                        boundsStart: bounds.start,
                        columnStart: column.columnStart,
                        gaps: clipGaps
                    )
                )
            }
        }

        for track in sourceTracks {
            let trackGaps = gaps(slotID: track.trackID, trackID: track.trackID, in: clipGaps)
            guard !trackGaps.isEmpty else { continue }
            guard !regions.contains(where: { $0.slotID == track.trackID && $0.trackID == track.trackID }) else {
                continue
            }
            regions.append(
                contentsOf: ClipRegionStore.defaultSourceTrackRegions(
                    trackID: track.trackID,
                    trimStart: track.trimStart,
                    trimEnd: track.trimEnd,
                    gaps: clipGaps
                )
            )
        }

        return regions
    }

    /// Trims, splits, or removes an arrangement clip based on a timeline range selection.
    /// Returns `true` when the clip was removed entirely.
    @discardableResult
    static func deleteVisibleRange(
        slotID: UUID,
        trackID: UUID,
        rangeStart: TimeInterval,
        rangeEnd: TimeInterval,
        sections: [ArrangementDisplaySection],
        marker: ArrangementMarker,
        markers: [ArrangementMarker],
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        sourceDuration: TimeInterval,
        clipTrims: inout [ArrangementClipTrim],
        removedClips: inout [ArrangementRemovedClip],
        clipGaps: inout [ArrangementClipGap],
        clipRegions: inout [ClipRegion],
        columnStart: TimeInterval
    ) -> Bool {
        let sortedMarkers = markers.sortedByTime
        let slotSections = sections
            .filter { $0.slotID == slotID }
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        guard let visibleStart = slotSections.first?.timelineStartSeconds,
              let visibleEnd = slotSections.last?.timelineEndSeconds else {
            return false
        }

        let snapped = MeasureTiming.snapTimelineRangeToGrid(
            start: rangeStart,
            end: rangeEnd,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let selectionStart = max(snapped.start, visibleStart)
        let selectionEnd = min(snapped.end, visibleEnd)
        guard selectionEnd - selectionStart >= minimumClipDuration else { return false }

        guard let sourceRange = trimmedSourceRange(
            slot: ArrangementSlot(id: slotID, markerID: marker.id),
            trackID: trackID,
            marker: marker,
            sortedMarkers: sortedMarkers,
            clipTrims: clipTrims,
            sourceDuration: sourceDuration
        ) else { return false }

        let bounds = markerSourceRange(
            for: marker,
            sortedMarkers: sortedMarkers,
            sourceDuration: sourceDuration
        )

        ensureClipRegions(
            slotID: slotID,
            trackID: trackID,
            markerID: marker.id,
            sourceRange: sourceRange,
            boundsStart: bounds.start,
            columnStart: columnStart,
            clipGaps: clipGaps,
            clipRegions: &clipRegions
        )
        clipGaps.removeAll { $0.slotID == slotID && $0.trackID == trackID }

        let removedEntirely = ClipRegionStore.deleteTimelineRange(
            slotID: slotID,
            trackID: trackID,
            rangeStart: selectionStart,
            rangeEnd: selectionEnd,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            in: &clipRegions
        )

        if removedEntirely {
            removeClip(
                slotID: slotID,
                trackID: trackID,
                clipTrims: &clipTrims,
                removedClips: &removedClips,
                clipGaps: &clipGaps,
                clipRegions: &clipRegions
            )
            return true
        }

        if ClipRegionStore.regions(slotID: slotID, trackID: trackID, in: clipRegions).isEmpty {
            removeClip(
                slotID: slotID,
                trackID: trackID,
                clipTrims: &clipTrims,
                removedClips: &removedClips,
                clipGaps: &clipGaps,
                clipRegions: &clipRegions
            )
            return true
        }

        return false
    }

    @discardableResult
    static func splitRegion(
        regionID: UUID,
        trackID: UUID,
        at timelineTime: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        clipRegions: inout [ClipRegion]
    ) -> UUID? {
        ClipRegionStore.splitRegion(
            regionID: regionID,
            trackID: trackID,
            at: timelineTime,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            in: &clipRegions
        )
    }

    @discardableResult
    static func joinRegions(
        firstID: UUID,
        secondID: UUID,
        trackID: UUID,
        clipRegions: inout [ClipRegion]
    ) -> UUID? {
        ClipRegionStore.joinRegions(firstID: firstID, secondID: secondID, trackID: trackID, in: &clipRegions)
    }

    @discardableResult
    static func deleteRegion(
        regionID: UUID,
        slotID: UUID,
        trackID: UUID,
        clipTrims: inout [ArrangementClipTrim],
        removedClips: inout [ArrangementRemovedClip],
        clipGaps: inout [ArrangementClipGap],
        clipRegions: inout [ClipRegion]
    ) -> Bool {
        let deleted = ClipRegionStore.deleteRegion(regionID: regionID, trackID: trackID, in: &clipRegions)
        guard deleted else { return false }

        if ClipRegionStore.regions(slotID: slotID, trackID: trackID, in: clipRegions).isEmpty {
            removeClip(
                slotID: slotID,
                trackID: trackID,
                clipTrims: &clipTrims,
                removedClips: &removedClips,
                clipGaps: &clipGaps,
                clipRegions: &clipRegions
            )
            return true
        }
        return false
    }

    static func clampedTrims(
        slotID: UUID,
        trackID: UUID,
        marker: ArrangementMarker,
        markers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        sourceDuration: TimeInterval
    ) -> (leading: TimeInterval, trailing: TimeInterval) {
        clampedTrims(
            slotID: slotID,
            trackID: trackID,
            marker: marker,
            sortedMarkers: markers.sortedByTime,
            clipTrims: clipTrims,
            sourceDuration: sourceDuration
        )
    }

    private static func clampedTrims(
        slotID: UUID,
        trackID: UUID,
        marker: ArrangementMarker,
        sortedMarkers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        sourceDuration: TimeInterval
    ) -> (leading: TimeInterval, trailing: TimeInterval) {
        let bounds = markerSourceRange(for: marker, sortedMarkers: sortedMarkers, sourceDuration: sourceDuration)
        let markerDuration = bounds.end - bounds.start
        let maxTrim = max(0, markerDuration - minimumClipDuration)

        let raw = trims(slotID: slotID, trackID: trackID, in: clipTrims)
        let leading = min(max(0, raw.leading), maxTrim)
        let trailing = min(max(0, raw.trailing), max(0, maxTrim - leading))
        return (leading, trailing)
    }

    static func trimmedSourceRange(
        slot: ArrangementSlot,
        trackID: UUID,
        marker: ArrangementMarker,
        markers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        sourceDuration: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval)? {
        trimmedSourceRange(
            slot: slot,
            trackID: trackID,
            marker: marker,
            sortedMarkers: markers.sortedByTime,
            clipTrims: clipTrims,
            sourceDuration: sourceDuration
        )
    }

    private static func trimmedSourceRange(
        slot: ArrangementSlot,
        trackID: UUID,
        marker: ArrangementMarker,
        sortedMarkers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        sourceDuration: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval)? {
        let bounds = markerSourceRange(for: marker, sortedMarkers: sortedMarkers, sourceDuration: sourceDuration)
        let trims = clampedTrims(
            slotID: slot.id,
            trackID: trackID,
            marker: marker,
            sortedMarkers: sortedMarkers,
            clipTrims: clipTrims,
            sourceDuration: sourceDuration
        )
        let effectiveStart = bounds.start + trims.leading
        let effectiveEnd = bounds.end - trims.trailing
        guard effectiveEnd - effectiveStart >= minimumClipDuration else { return nil }
        return (effectiveStart, effectiveEnd)
    }

    static func clipDuration(
        slot: ArrangementSlot,
        trackID: UUID,
        marker: ArrangementMarker,
        markers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        guard let range = trimmedSourceRange(
            slot: slot,
            trackID: trackID,
            marker: marker,
            markers: markers,
            clipTrims: clipTrims,
            sourceDuration: sourceDuration
        ) else { return 0 }
        return range.end - range.start
    }

    static func trackDisplaySections(
        for trackID: UUID,
        slots: [ArrangementSlot],
        markers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = [],
        trackIDs: [UUID],
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> [ArrangementDisplaySection] {
        let inputs = makeLayoutInputs(
            markers: markers,
            trackIDs: trackIDs,
            sourceDurationForTrack: sourceDurationForTrack
        )
        return trackDisplaySections(
            for: trackID,
            slots: slots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            inputs: inputs
        )
    }

    static func trackDisplaySections(
        for trackID: UUID,
        slots: [ArrangementSlot],
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap] = [],
        clipRegions: [ClipRegion] = [],
        inputs: ArrangementLayoutInputs
    ) -> [ArrangementDisplaySection] {
        guard usesSectionedTrackLayout(
            slots: slots,
            markers: inputs.sortedMarkers,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions
        ) else {
            return []
        }

        let columns = arrangementColumns(slots: slots, inputs: inputs)
        return trackDisplaySections(
            for: trackID,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            columns: columns,
            inputs: inputs
        )
    }

    private static func trackDisplaySections(
        for trackID: UUID,
        clipTrims: [ArrangementClipTrim],
        removedClips: [ArrangementRemovedClip],
        clipGaps: [ArrangementClipGap],
        clipRegions: [ClipRegion],
        columns: [ArrangementColumn],
        inputs: ArrangementLayoutInputs
    ) -> [ArrangementDisplaySection] {
        let sourceDuration = inputs.sourceDurationForTrack(trackID)
        var sections: [ArrangementDisplaySection] = []

        for column in columns {
            let columnEnd = column.columnStart + column.columnWidth

            if isClipRemoved(slotID: column.slot.id, trackID: trackID, in: removedClips) {
                continue
            }

            let storedRegions = ClipRegionStore.regions(
                slotID: column.slot.id,
                trackID: trackID,
                in: clipRegions
            )
            if !storedRegions.isEmpty {
                let trims = clampedTrims(
                    slotID: column.slot.id,
                    trackID: trackID,
                    marker: column.marker,
                    sortedMarkers: inputs.sortedMarkers,
                    clipTrims: clipTrims,
                    sourceDuration: sourceDuration
                )
                let visibleTimelineStart = column.columnStart + trims.leading
                let visibleTimelineEnd = columnEnd - trims.trailing

                for region in storedRegions {
                    guard let clippedRegion = clippedRegion(
                        region,
                        visibleTimelineStart: visibleTimelineStart,
                        visibleTimelineEnd: visibleTimelineEnd
                    ) else {
                        continue
                    }

                    sections.append(
                        ClipRegionStore.displaySection(
                            from: clippedRegion,
                            name: column.marker.name,
                            columnStart: column.columnStart,
                            columnEnd: columnEnd
                        )
                    )
                }
                continue
            }

            guard column.columnWidth >= minimumClipDuration,
                  let sourceRange = trimmedSourceRange(
                      slot: column.slot,
                      trackID: trackID,
                      marker: column.marker,
                      sortedMarkers: inputs.sortedMarkers,
                      clipTrims: clipTrims,
                      sourceDuration: sourceDuration
                  ) else {
                continue
            }

            let bounds = markerSourceRange(
                for: column.marker,
                sortedMarkers: inputs.sortedMarkers,
                sourceDuration: sourceDuration
            )
            let slotGaps = gaps(slotID: column.slot.id, trackID: trackID, in: clipGaps)
            let segments = sourceSegments(
                from: sourceRange.start,
                to: sourceRange.end,
                excluding: slotGaps
            )
            guard !segments.isEmpty else { continue }

            for (index, segment) in segments.enumerated() {
                let sectionID = segments.count == 1
                    ? column.slot.id
                    : segmentID(slotID: column.slot.id, index: index)
                let timelineStart = column.columnStart + (segment.start - bounds.start)
                let timelineEnd = column.columnStart + (segment.end - bounds.start)

                sections.append(
                    ArrangementDisplaySection(
                        id: sectionID,
                        slotID: column.slot.id,
                        markerID: column.marker.id,
                        name: column.marker.name,
                        sourceStartSeconds: segment.start,
                        sourceEndSeconds: segment.end,
                        timelineStartSeconds: timelineStart,
                        timelineEndSeconds: timelineEnd,
                        columnStartSeconds: column.columnStart,
                        columnEndSeconds: columnEnd
                    )
                )
            }
        }

        // Keep adjacent source-order sections as one clip; only cut at discontinuities
        // created by rearrange / duplicate / remove.
        return coalesceContiguousTrackSections(sections)
    }

    /// Joins neighboring clips that play contiguous source audio on a contiguous timeline.
    /// A moved or duplicated section breaks source adjacency and remains its own cut.
    static func coalesceContiguousTrackSections(
        _ sections: [ArrangementDisplaySection]
    ) -> [ArrangementDisplaySection] {
        guard let first = sections.first else { return [] }

        var coalesced: [ArrangementDisplaySection] = []
        var current = first

        for next in sections.dropFirst() {
            let sourceAbuts = abs(current.sourceEndSeconds - next.sourceStartSeconds) <= 0.000_1
            let timelineAbuts = abs(current.timelineEndSeconds - next.timelineStartSeconds) <= 0.000_1
            if sourceAbuts, timelineAbuts {
                current = ArrangementDisplaySection(
                    id: current.id,
                    slotID: current.slotID,
                    markerID: current.markerID,
                    name: current.name,
                    sourceStartSeconds: current.sourceStartSeconds,
                    sourceEndSeconds: next.sourceEndSeconds,
                    timelineStartSeconds: current.timelineStartSeconds,
                    timelineEndSeconds: next.timelineEndSeconds,
                    columnStartSeconds: current.columnStartSeconds,
                    columnEndSeconds: next.columnEndSeconds
                )
            } else {
                coalesced.append(current)
                current = next
            }
        }

        coalesced.append(current)
        return coalesced
    }

    static func rulerDisplaySections(
        slots: [ArrangementSlot],
        markers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        trackIDs: [UUID],
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> [ArrangementDisplaySection] {
        let inputs = makeLayoutInputs(
            markers: markers,
            trackIDs: trackIDs,
            sourceDurationForTrack: sourceDurationForTrack
        )
        let columns = arrangementColumns(slots: slots, inputs: inputs)
        return rulerDisplaySections(columns: columns, inputs: inputs)
    }

    private static func rulerDisplaySections(
        columns: [ArrangementColumn],
        inputs: ArrangementLayoutInputs
    ) -> [ArrangementDisplaySection] {
        let maxSourceDuration = inputs.trackIDs.map(inputs.sourceDurationForTrack).max() ?? 1
        var sections: [ArrangementDisplaySection] = []

        for column in columns {
            guard column.columnWidth >= minimumClipDuration else { continue }

            let bounds = markerSourceRange(
                for: column.marker,
                sortedMarkers: inputs.sortedMarkers,
                sourceDuration: maxSourceDuration
            )
            let columnEnd = column.columnStart + column.columnWidth

            sections.append(
                ArrangementDisplaySection(
                    id: column.slot.id,
                    slotID: column.slot.id,
                    markerID: column.marker.id,
                    name: column.marker.name,
                    sourceStartSeconds: bounds.start,
                    sourceEndSeconds: bounds.end,
                    timelineStartSeconds: column.columnStart,
                    timelineEndSeconds: columnEnd,
                    columnStartSeconds: column.columnStart,
                    columnEndSeconds: columnEnd
                )
            )
        }

        return sections
    }

    /// Ruler sections placed at absolute source times for identity arrangements
    /// (continuous tracks with section markers, no packing/cutting).
    private static func sourceAlignedRulerSections(
        slots: [ArrangementSlot],
        inputs: ArrangementLayoutInputs
    ) -> [ArrangementDisplaySection] {
        let maxSourceDuration = inputs.trackIDs.map(inputs.sourceDurationForTrack).max() ?? 1
        var sections: [ArrangementDisplaySection] = []

        for slot in slots {
            guard let marker = inputs.markersByID[slot.markerID] else { continue }
            let bounds = markerSourceRange(
                for: marker,
                sortedMarkers: inputs.sortedMarkers,
                sourceDuration: maxSourceDuration
            )
            guard bounds.end - bounds.start >= minimumClipDuration else { continue }

            sections.append(
                ArrangementDisplaySection(
                    id: slot.id,
                    slotID: slot.id,
                    markerID: marker.id,
                    name: marker.name,
                    sourceStartSeconds: bounds.start,
                    sourceEndSeconds: bounds.end,
                    timelineStartSeconds: bounds.start,
                    timelineEndSeconds: bounds.end,
                    columnStartSeconds: bounds.start,
                    columnEndSeconds: bounds.end
                )
            )
        }

        return sections
    }

    static func masterTimelineDuration(
        slots: [ArrangementSlot],
        markers: [ArrangementMarker],
        clipTrims: [ArrangementClipTrim],
        trackIDs: [UUID],
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> TimeInterval {
        rulerDisplaySections(
            slots: slots,
            markers: markers,
            clipTrims: clipTrims,
            trackIDs: trackIDs,
            sourceDurationForTrack: sourceDurationForTrack
        ).last?.timelineEndSeconds ?? 0
    }

    /// Timeline extent for playback and editor sizing. When explicit clip regions end before the
    /// marker ruler (for example after ripple delete), honour the shorter audible timeline.
    static func effectiveTimelineDuration(
        rulerSections: [ArrangementDisplaySection],
        trackSections: [UUID: [ArrangementDisplaySection]]
    ) -> TimeInterval {
        let rulerEnd = rulerSections.last?.timelineEndSeconds ?? 0
        let trackEnd = trackSections.values
            .flatMap { $0 }
            .map(\.timelineEndSeconds)
            .max() ?? 0

        if trackEnd > 0, trackEnd < rulerEnd - 0.001 {
            return max(trackEnd, minimumClipDuration)
        }
        return max(rulerEnd, trackEnd, minimumClipDuration)
    }

    /// Clamps marker-ruler sections to the audible timeline so section markers stay aligned
    /// with clip regions after edits such as ripple delete.
    private static func rulerSectionsAlignedToTimelineDuration(
        _ sections: [ArrangementDisplaySection],
        duration: TimeInterval
    ) -> [ArrangementDisplaySection] {
        sections.compactMap { section in
            alignedRulerSection(section, to: duration)
        }
    }

    private static func clippedRegion(
        _ region: ClipRegion,
        visibleTimelineStart: TimeInterval,
        visibleTimelineEnd: TimeInterval
    ) -> ClipRegion? {
        let timelineStart = max(region.timelineStartSeconds, visibleTimelineStart)
        let timelineEnd = min(region.timelineEndSeconds, visibleTimelineEnd)
        guard timelineEnd - timelineStart >= minimumClipDuration else { return nil }

        let regionDuration = region.timelineEndSeconds - region.timelineStartSeconds
        guard regionDuration >= minimumClipDuration else { return nil }

        let sourceDuration = region.sourceEndSeconds - region.sourceStartSeconds
        let startRatio = (timelineStart - region.timelineStartSeconds) / regionDuration
        let endRatio = (timelineEnd - region.timelineStartSeconds) / regionDuration

        return ClipRegion(
            id: region.id,
            slotID: region.slotID,
            trackID: region.trackID,
            markerID: region.markerID,
            sourceStartSeconds: region.sourceStartSeconds + sourceDuration * startRatio,
            sourceEndSeconds: region.sourceStartSeconds + sourceDuration * endRatio,
            timelineStartSeconds: timelineStart,
            timelineEndSeconds: timelineEnd
        )
    }

    private static func alignedLayoutSnapshot(
        rulerSections: [ArrangementDisplaySection],
        trackSections: [UUID: [ArrangementDisplaySection]]
    ) -> ArrangementLayoutSnapshot {
        let duration = effectiveTimelineDuration(
            rulerSections: rulerSections,
            trackSections: trackSections
        )
        let alignedRuler = rulerSectionsAlignedToTimelineDuration(rulerSections, duration: duration)
        return ArrangementLayoutSnapshot(
            rulerSections: alignedRuler,
            trackSections: trackSections
        )
    }

    private static func alignedRulerSection(
        _ section: ArrangementDisplaySection,
        to duration: TimeInterval
    ) -> ArrangementDisplaySection? {
        guard section.timelineStartSeconds < duration - minimumClipDuration else { return nil }

        let timelineEnd = min(section.timelineEndSeconds, duration)
        guard timelineEnd - section.timelineStartSeconds >= minimumClipDuration else { return nil }

        if abs(timelineEnd - section.timelineEndSeconds) <= 0.001,
           section.columnEndSeconds <= duration + 0.001 {
            return section
        }

        return ArrangementDisplaySection(
            id: section.id,
            slotID: section.slotID,
            markerID: section.markerID,
            name: section.name,
            sourceStartSeconds: section.sourceStartSeconds,
            sourceEndSeconds: section.sourceEndSeconds,
            timelineStartSeconds: section.timelineStartSeconds,
            timelineEndSeconds: timelineEnd,
            columnStartSeconds: section.columnStartSeconds,
            columnEndSeconds: min(section.columnEndSeconds, duration)
        )
    }

    static func setTrims(
        slotID: UUID,
        trackID: UUID,
        leading: TimeInterval,
        trailing: TimeInterval,
        in clipTrims: inout [ArrangementClipTrim]
    ) {
        if let index = clipTrims.firstIndex(where: { $0.slotID == slotID && $0.trackID == trackID }) {
            clipTrims[index].leadingTrim = leading
            clipTrims[index].trailingTrim = trailing
        } else {
            clipTrims.append(
                ArrangementClipTrim(
                    slotID: slotID,
                    trackID: trackID,
                    leadingTrim: leading,
                    trailingTrim: trailing
                )
            )
        }
    }

    private struct ArrangementColumn {
        let slot: ArrangementSlot
        let marker: ArrangementMarker
        let columnStart: TimeInterval
        let columnWidth: TimeInterval
    }

    private static func arrangementColumns(
        slots: [ArrangementSlot],
        inputs: ArrangementLayoutInputs
    ) -> [ArrangementColumn] {
        var masterTimeline: TimeInterval = 0
        var columns: [ArrangementColumn] = []

        for slot in slots {
            guard let marker = inputs.markersByID[slot.markerID] else { continue }

            let columnWidth = slotColumnWidth(
                marker: marker,
                sortedMarkers: inputs.sortedMarkers,
                trackIDs: inputs.trackIDs,
                sourceDurationForTrack: inputs.sourceDurationForTrack
            )
            columns.append(
                ArrangementColumn(
                    slot: slot,
                    marker: marker,
                    columnStart: masterTimeline,
                    columnWidth: columnWidth
                )
            )
            masterTimeline += columnWidth
        }

        return columns
    }

    private static func slotColumnWidth(
        marker: ArrangementMarker,
        sortedMarkers: [ArrangementMarker],
        trackIDs: [UUID],
        sourceDurationForTrack: (UUID) -> TimeInterval
    ) -> TimeInterval {
        trackIDs
            .map { trackID in
                untrimmedClipDuration(
                    marker: marker,
                    sortedMarkers: sortedMarkers,
                    sourceDuration: sourceDurationForTrack(trackID)
                )
            }
            .max() ?? 0
    }

    private static func slotColumnWidth(
        marker: ArrangementMarker,
        markers: [ArrangementMarker],
        trackIDs: [UUID],
        sourceDurationForTrack: (UUID) -> TimeInterval
    ) -> TimeInterval {
        slotColumnWidth(
            marker: marker,
            sortedMarkers: markers.sortedByTime,
            trackIDs: trackIDs,
            sourceDurationForTrack: sourceDurationForTrack
        )
    }

    private static func untrimmedClipDuration(
        marker: ArrangementMarker,
        sortedMarkers: [ArrangementMarker],
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        let bounds = markerSourceRange(for: marker, sortedMarkers: sortedMarkers, sourceDuration: sourceDuration)
        return max(0, bounds.end - bounds.start)
    }

    private static func untrimmedClipDuration(
        marker: ArrangementMarker,
        markers: [ArrangementMarker],
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        untrimmedClipDuration(
            marker: marker,
            sortedMarkers: markers.sortedByTime,
            sourceDuration: sourceDuration
        )
    }

    private static func validated(_ arrangement: SongArrangement, markers: [ArrangementMarker]) -> SongArrangement {
        var validSlots = validatedSlots(arrangement.slots, markers: markers)
        var clipTrims = arrangement.clipTrims
        var removedClips = arrangement.removedClips
        var clipGaps = arrangement.clipGaps
        var clipRegions = arrangement.clipRegions
        var loopSlotIDs = arrangement.loopSlotIDs

        if validSlots.isEmpty,
           !markers.isEmpty,
           arrangement.slots.count == markers.sortedByTime.count {
            let recoveredSlots = defaultSlots(from: markers)
            let slotIDMap = Dictionary(
                uniqueKeysWithValues: zip(arrangement.slots.map(\.id), recoveredSlots.map(\.id))
            )
            validSlots = recoveredSlots
            clipTrims = arrangement.clipTrims.compactMap { trim in
                guard let newSlotID = slotIDMap[trim.slotID] else { return nil }
                return ArrangementClipTrim(
                    slotID: newSlotID,
                    trackID: trim.trackID,
                    leadingTrim: trim.leadingTrim,
                    trailingTrim: trim.trailingTrim
                )
            }
            removedClips = arrangement.removedClips.compactMap { removed in
                guard let newSlotID = slotIDMap[removed.slotID] else { return nil }
                return ArrangementRemovedClip(slotID: newSlotID, trackID: removed.trackID)
            }
            clipGaps = arrangement.clipGaps.compactMap { gap in
                guard let newSlotID = slotIDMap[gap.slotID] else { return nil }
                return ArrangementClipGap(
                    slotID: newSlotID,
                    trackID: gap.trackID,
                    sourceStartSeconds: gap.sourceStartSeconds,
                    sourceEndSeconds: gap.sourceEndSeconds
                )
            }
            clipRegions = arrangement.clipRegions.compactMap { region in
                guard let newSlotID = slotIDMap[region.slotID] else { return nil }
                return ClipRegion(
                    id: region.id,
                    slotID: newSlotID,
                    trackID: region.trackID,
                    markerID: region.markerID,
                    sourceStartSeconds: region.sourceStartSeconds,
                    sourceEndSeconds: region.sourceEndSeconds,
                    timelineStartSeconds: region.timelineStartSeconds,
                    timelineEndSeconds: region.timelineEndSeconds
                )
            }
            loopSlotIDs = Set(arrangement.loopSlotIDs.compactMap { slotIDMap[$0] })
        }

        let validSlotIDs = Set(validSlots.map(\.id))
        let validTrims = clipTrims.filter { validSlotIDs.contains($0.slotID) || $0.slotID == $0.trackID }
        let validRemoved = removedClips.filter { validSlotIDs.contains($0.slotID) || $0.slotID == $0.trackID }
        let validGaps = clipGaps.filter { validSlotIDs.contains($0.slotID) || $0.slotID == $0.trackID }
        let validRegions = clipRegions.filter { validSlotIDs.contains($0.slotID) || $0.slotID == $0.trackID }
        loopSlotIDs = loopSlotIDs.intersection(validSlotIDs)
        return SongArrangement(
            slots: validSlots,
            clipTrims: validTrims,
            removedClips: validRemoved,
            clipGaps: validGaps,
            clipRegions: validRegions,
            loopSlotIDs: loopSlotIDs
        )
    }

    private static func validatedSlots(_ slots: [ArrangementSlot], markers: [ArrangementMarker]) -> [ArrangementSlot] {
        let validMarkerIDs = Set(markers.map(\.id))
        return slots.filter { validMarkerIDs.contains($0.markerID) }
    }
}
