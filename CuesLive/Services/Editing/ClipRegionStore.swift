import Foundation

/// Logic-style non-destructive clip regions with explicit timeline and source bounds.
enum ClipRegionStore {
    static func regions(
        slotID: UUID,
        trackID: UUID,
        in clipRegions: [ClipRegion]
    ) -> [ClipRegion] {
        clipRegions
            .filter { $0.slotID == slotID && $0.trackID == trackID }
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
    }

    /// All stored regions for a track, including arrangement-slot and source-track regions.
    static func regions(
        forTrack trackID: UUID,
        in clipRegions: [ClipRegion]
    ) -> [ClipRegion] {
        clipRegions
            .filter { $0.trackID == trackID }
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
    }

    static func hasStoredRegions(
        slotID: UUID,
        trackID: UUID,
        in clipRegions: [ClipRegion]
    ) -> Bool {
        clipRegions.contains { $0.slotID == slotID && $0.trackID == trackID }
    }

    static func removeAllRegions(
        slotID: UUID,
        trackID: UUID,
        in clipRegions: inout [ClipRegion]
    ) {
        clipRegions.removeAll { $0.slotID == slotID && $0.trackID == trackID }
    }

    /// Builds default regions from legacy trims + gaps when no explicit regions exist.
    static func defaultRegions(
        slotID: UUID,
        trackID: UUID,
        markerID: UUID,
        sourceRange: (start: TimeInterval, end: TimeInterval),
        boundsStart: TimeInterval,
        columnStart: TimeInterval,
        gaps: [ArrangementClipGap]
    ) -> [ClipRegion] {
        let slotGaps = gaps
            .filter { $0.slotID == slotID && $0.trackID == trackID }
            .sorted { $0.sourceStartSeconds < $1.sourceStartSeconds }

        let segments = SongArrangementStore.sourceSegments(
            from: sourceRange.start,
            to: sourceRange.end,
            excluding: slotGaps
        )

        return segments.enumerated().map { index, segment in
            let regionID = segments.count == 1
                ? slotID
                : SongArrangementStore.segmentID(slotID: slotID, index: index)
            return ClipRegion(
                id: regionID,
                slotID: slotID,
                trackID: trackID,
                markerID: markerID,
                sourceStartSeconds: segment.start,
                sourceEndSeconds: segment.end,
                timelineStartSeconds: columnStart + (segment.start - boundsStart),
                timelineEndSeconds: columnStart + (segment.end - boundsStart)
            )
        }
    }

    static func defaultSourceTrackRegions(
        trackID: UUID,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        gaps: [ArrangementClipGap]
    ) -> [ClipRegion] {
        let trackGaps = gaps.filter { $0.slotID == trackID && $0.trackID == trackID }
        let segments = SongArrangementStore.sourceSegments(
            from: trimStart,
            to: trimEnd,
            excluding: trackGaps
        )

        return segments.enumerated().map { index, segment in
            ClipRegion(
                id: segments.count == 1 ? trackID : SongArrangementStore.segmentID(slotID: trackID, index: index),
                slotID: trackID,
                trackID: trackID,
                markerID: trackID,
                sourceStartSeconds: segment.start,
                sourceEndSeconds: segment.end,
                timelineStartSeconds: segment.start,
                timelineEndSeconds: segment.end
            )
        }
    }

    static func region(
        id: UUID,
        trackID: UUID,
        in clipRegions: [ClipRegion]
    ) -> ClipRegion? {
        clipRegions.first { $0.id == id && $0.trackID == trackID }
    }

    enum RegionTrimEdge {
        case leading
        case trailing
    }

    /// Adjusts one edge of a region, keeping source and timeline in sync (Logic-style).
    static func regionByTrimmingEdge(
        _ baseline: ClipRegion,
        edge: RegionTrimEdge,
        timelineOffset: TimeInterval,
        in clipRegions: [ClipRegion],
        boundsStart: TimeInterval,
        boundsEnd: TimeInterval
    ) -> ClipRegion {
        let minDuration = SongArrangementStore.minimumClipDuration
        let siblings = clipRegions
            .filter { $0.slotID == baseline.slotID && $0.trackID == baseline.trackID && $0.id != baseline.id }
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }

        let tolerance: TimeInterval = 0.02
        let previous = siblings.last { $0.timelineEndSeconds <= baseline.timelineStartSeconds + tolerance }
        let next = siblings.first { $0.timelineStartSeconds >= baseline.timelineEndSeconds - tolerance }

        switch edge {
        case .leading:
            let minStart = max(boundsStart, previous?.timelineEndSeconds ?? boundsStart)
            let maxStart = baseline.timelineEndSeconds - minDuration
            let newStart = min(max(baseline.timelineStartSeconds + timelineOffset, minStart), maxStart)
            return trimmedRegion(baseline, newTimelineStart: newStart, newTimelineEnd: nil)
        case .trailing:
            let maxEnd = min(boundsEnd, next?.timelineStartSeconds ?? boundsEnd)
            let minEnd = baseline.timelineStartSeconds + minDuration
            let newEnd = min(max(baseline.timelineEndSeconds + timelineOffset, minEnd), maxEnd)
            return trimmedRegion(baseline, newTimelineStart: nil, newTimelineEnd: newEnd)
        }
    }

    @discardableResult
    static func splitRegion(
        regionID: UUID,
        trackID: UUID,
        at timelineTime: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        in clipRegions: inout [ClipRegion]
    ) -> UUID? {
        guard let index = clipRegions.firstIndex(where: { $0.id == regionID && $0.trackID == trackID }) else {
            return nil
        }
        let region = clipRegions[index]
        let snapped = MeasureTiming.snapToNearestBeat(
            timelineTime,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let splitTime = min(max(snapped, region.timelineStartSeconds), region.timelineEndSeconds)
        let minDuration = SongArrangementStore.minimumClipDuration

        guard splitTime - region.timelineStartSeconds >= minDuration,
              region.timelineEndSeconds - splitTime >= minDuration else {
            return nil
        }

        let duration = region.timelineEndSeconds - region.timelineStartSeconds
        guard duration > 0 else { return nil }
        let ratio = (splitTime - region.timelineStartSeconds) / duration
        let sourceDuration = region.sourceEndSeconds - region.sourceStartSeconds
        let sourceSplit = region.sourceStartSeconds + sourceDuration * ratio

        let rightID = UUID()
        let left = ClipRegion(
            id: region.id,
            slotID: region.slotID,
            trackID: region.trackID,
            markerID: region.markerID,
            sourceStartSeconds: region.sourceStartSeconds,
            sourceEndSeconds: sourceSplit,
            timelineStartSeconds: region.timelineStartSeconds,
            timelineEndSeconds: splitTime
        )
        let right = ClipRegion(
            id: rightID,
            slotID: region.slotID,
            trackID: region.trackID,
            markerID: region.markerID,
            sourceStartSeconds: sourceSplit,
            sourceEndSeconds: region.sourceEndSeconds,
            timelineStartSeconds: splitTime,
            timelineEndSeconds: region.timelineEndSeconds
        )

        clipRegions[index] = left
        clipRegions.insert(right, at: index + 1)
        return rightID
    }

    @discardableResult
    static func joinRegions(
        firstID: UUID,
        secondID: UUID,
        trackID: UUID,
        in clipRegions: inout [ClipRegion]
    ) -> UUID? {
        guard let firstIndex = clipRegions.firstIndex(where: { $0.id == firstID && $0.trackID == trackID }),
              let secondIndex = clipRegions.firstIndex(where: { $0.id == secondID && $0.trackID == trackID }),
              firstIndex != secondIndex else {
            return nil
        }

        let first = clipRegions[firstIndex]
        let second = clipRegions[secondIndex]
        guard first.slotID == second.slotID,
              first.trackID == second.trackID else {
            return nil
        }

        let leading = first.timelineStartSeconds <= second.timelineStartSeconds ? first : second
        let trailing = leading.id == first.id ? second : first
        let tolerance: TimeInterval = 0.02

        guard abs(leading.timelineEndSeconds - trailing.timelineStartSeconds) <= tolerance
            || abs(trailing.timelineEndSeconds - leading.timelineStartSeconds) <= tolerance else {
            return nil
        }

        let mergedStart = min(leading.timelineStartSeconds, trailing.timelineStartSeconds)
        let mergedEnd = max(leading.timelineEndSeconds, trailing.timelineEndSeconds)
        let mergedSourceStart = min(leading.sourceStartSeconds, trailing.sourceStartSeconds)
        let mergedSourceEnd = max(leading.sourceEndSeconds, trailing.sourceEndSeconds)

        let merged = ClipRegion(
            id: leading.id,
            slotID: leading.slotID,
            trackID: leading.trackID,
            markerID: leading.markerID,
            sourceStartSeconds: mergedSourceStart,
            sourceEndSeconds: mergedSourceEnd,
            timelineStartSeconds: mergedStart,
            timelineEndSeconds: mergedEnd
        )

        clipRegions.removeAll {
            $0.trackID == first.trackID && ($0.id == first.id || $0.id == second.id)
        }
        clipRegions.append(merged)
        return merged.id
    }

    @discardableResult
    static func deleteRegion(
        regionID: UUID,
        trackID: UUID,
        in clipRegions: inout [ClipRegion]
    ) -> Bool {
        let before = clipRegions.count
        clipRegions.removeAll { $0.id == regionID && $0.trackID == trackID }
        return clipRegions.count < before
    }

    @discardableResult
    static func deleteTimelineRange(
        slotID: UUID,
        trackID: UUID,
        rangeStart: TimeInterval,
        rangeEnd: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        in clipRegions: inout [ClipRegion]
    ) -> Bool {
        let snapped = MeasureTiming.snapTimelineRangeToGrid(
            start: rangeStart,
            end: rangeEnd,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let selectionStart = snapped.start
        let selectionEnd = snapped.end
        let minDuration = SongArrangementStore.minimumClipDuration
        guard selectionEnd - selectionStart >= minDuration else { return false }

        let affected = regions(slotID: slotID, trackID: trackID, in: clipRegions)
        guard !affected.isEmpty else { return false }

        let visibleStart = affected.first!.timelineStartSeconds
        let visibleEnd = affected.last!.timelineEndSeconds
        let tolerance: TimeInterval = 0.02

        if selectionStart <= visibleStart + tolerance, selectionEnd >= visibleEnd - tolerance {
            removeAllRegions(slotID: slotID, trackID: trackID, in: &clipRegions)
            return true
        }

        var rebuilt: [ClipRegion] = clipRegions.filter { !($0.slotID == slotID && $0.trackID == trackID) }

        for region in affected {
            let overlapStart = max(selectionStart, region.timelineStartSeconds)
            let overlapEnd = min(selectionEnd, region.timelineEndSeconds)

            if overlapEnd - overlapStart < minDuration {
                rebuilt.append(region)
                continue
            }

            if selectionStart <= region.timelineStartSeconds + tolerance,
               selectionEnd >= region.timelineEndSeconds - tolerance {
                continue
            }

            if selectionStart <= region.timelineStartSeconds + tolerance {
                rebuilt.append(trimmedRegion(region, newTimelineStart: selectionEnd))
                continue
            }

            if selectionEnd >= region.timelineEndSeconds - tolerance {
                rebuilt.append(trimmedRegion(region, newTimelineEnd: selectionStart))
                continue
            }

            let (left, right) = splitRegionAtTimeline(
                region,
                start: selectionStart,
                end: selectionEnd
            )
            rebuilt.append(left)
            rebuilt.append(right)
        }

        clipRegions = rebuilt.sorted {
            if $0.timelineStartSeconds != $1.timelineStartSeconds {
                return $0.timelineStartSeconds < $1.timelineStartSeconds
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        return false
    }

    private static func trimmedRegion(
        _ region: ClipRegion,
        newTimelineStart: TimeInterval? = nil,
        newTimelineEnd: TimeInterval? = nil
    ) -> ClipRegion {
        let timelineStart = newTimelineStart ?? region.timelineStartSeconds
        let timelineEnd = newTimelineEnd ?? region.timelineEndSeconds
        let duration = region.timelineEndSeconds - region.timelineStartSeconds
        guard duration > 0 else { return region }

        let sourceDuration = region.sourceEndSeconds - region.sourceStartSeconds
        let startRatio = (timelineStart - region.timelineStartSeconds) / duration
        let endRatio = (timelineEnd - region.timelineStartSeconds) / duration

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

    private static func splitRegionAtTimeline(
        _ region: ClipRegion,
        start: TimeInterval,
        end: TimeInterval
    ) -> (ClipRegion, ClipRegion) {
        let left = trimmedRegion(region, newTimelineEnd: start)
        let right = trimmedRegion(region, newTimelineStart: end)
        return (
            ClipRegion(
                id: region.id,
                slotID: region.slotID,
                trackID: region.trackID,
                markerID: region.markerID,
                sourceStartSeconds: left.sourceStartSeconds,
                sourceEndSeconds: left.sourceEndSeconds,
                timelineStartSeconds: left.timelineStartSeconds,
                timelineEndSeconds: left.timelineEndSeconds
            ),
            ClipRegion(
                id: UUID(),
                slotID: region.slotID,
                trackID: region.trackID,
                markerID: region.markerID,
                sourceStartSeconds: right.sourceStartSeconds,
                sourceEndSeconds: right.sourceEndSeconds,
                timelineStartSeconds: right.timelineStartSeconds,
                timelineEndSeconds: right.timelineEndSeconds
            )
        )
    }

    static func displaySection(
        from region: ClipRegion,
        name: String,
        columnStart: TimeInterval,
        columnEnd: TimeInterval
    ) -> ArrangementDisplaySection {
        ArrangementDisplaySection(
            id: region.id,
            slotID: region.slotID,
            markerID: region.markerID,
            name: name,
            sourceStartSeconds: region.sourceStartSeconds,
            sourceEndSeconds: region.sourceEndSeconds,
            timelineStartSeconds: region.timelineStartSeconds,
            timelineEndSeconds: region.timelineEndSeconds,
            columnStartSeconds: columnStart,
            columnEndSeconds: columnEnd
        )
    }
}
