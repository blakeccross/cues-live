import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditView {
    var clipEditorActions: ClipEditorActions {
        ClipEditorActions(
            canSplit: !clipSelection.isEmpty,
            canJoin: !clipSelection.isEmpty,
            canDuplicate: !clipSelection.isEmpty,
            canDeselect: !clipSelection.isEmpty,
            canAdjustGain: !clipSelection.isEmpty,
            canNudgeGain: !clipSelection.isEmpty,
            split: { splitSelectedClips(at: AudioEngineManager.shared.currentTime) },
            join: { joinSelectedClips() },
            duplicate: { duplicateSelectedClips() },
            deselectAll: { clipSelection.deselectAll() },
            adjustGain: { beginAdjustGain() },
            nudgeGainUp: { nudgeSelectedClipGain(by: 1) },
            nudgeGainDown: { nudgeSelectedClipGain(by: -1) }
        )
    }

    func removeClipSelection() {
        guard !clipSelection.isEmpty else { return }
        let ids = clipSelection.clipIDs
        commitTimelineEdit("Delete Clips") { timeline in
            ClipEditing.delete(clipIDs: ids, in: &timeline.clips)
        }
        clipSelection.deselectAll()
        clearMarkerCue(cancellingScheduledTransition: false)
    }


    func selectAllClips() {
        clipSelection = ClipSelection(timeline.clips.map(\.id))
    }

    /// Splits every selected clip that spans `time`; both halves stay selected.
    private func splitSelectedClips(at time: TimeInterval) {
        splitClips(clipSelection.clipIDs, at: [time])
    }

    /// Where Split cuts. A range is cut at both edges. An insertion is one cut.
    private var editSplitPoints: [TimeInterval] {
        if let selection = editSelection, selection.end - selection.start > ClipEditing.tolerance {
            return [selection.start, selection.end]
        }
        return [insertionTime]
    }

    /// Split from the clip menu, at the edit selection.
    /// A clip already in the selection splits with every other selected clip, and with every clip
    /// on a selected track that the cut runs through. Any other clip splits alone.
    private func splitAtEditSelection(clickedClipID: UUID, clipWasSelected: Bool) {
        if !clipWasSelected {
            clipSelection = ClipSelection([clickedClipID])
        }
        var ids = clipSelection.clipIDs
        if clipWasSelected {
            for clip in timeline.clips where selectedTrackIDs.contains(clip.trackID) && editSplitPoints.contains(where: clip.containsTimelineTime) {
                ids.insert(clip.id)
            }
        }
        splitClips(ids, at: editSplitPoints)
    }

    /// Splits `ids` at each time. Pieces from an earlier cut are included in the later ones.
    private func splitClips(_ ids: Set<UUID>, at times: [TimeInterval]) {
        let canSplit = timeline.clips.contains { clip in
            guard ids.contains(clip.id) else { return false }
            return times.contains { time in
                time - clip.timelineStartSeconds >= TrackClip.minimumDuration
                    && clip.timelineEndSeconds - time >= TrackClip.minimumDuration
            }
        }
        guard canSplit else { return }
        commitTimelineEdit("Split Clips") { timeline in
            let rightIDs = ClipEditing.split(clipIDs: ids, at: times, in: &timeline.clips)
            clipSelection.select(rightIDs)
        }
    }

    private func joinSelectedClips() {
        var joined = timeline.clips
        let remaining = ClipEditing.join(clipIDs: clipSelection.clipIDs, in: &joined)
        guard joined != timeline.clips else { return }
        commitTimelineEdit("Join Clips") { timeline in
            timeline.clips = joined
        }
        clipSelection = ClipSelection(remaining)
    }

    private func duplicateSelectedClips() {
        guard !clipSelection.isEmpty else { return }
        let ids = clipSelection.clipIDs
        commitTimelineEdit("Duplicate Clips") { timeline in
            clipSelection = ClipSelection(ClipEditing.duplicate(clipIDs: ids, in: &timeline.clips))
        }
    }

    private var selectedClips: [TrackClip] {
        timeline.clips.filter { clipSelection.contains($0.id) }
    }

    private func snappedToBeat(_ time: TimeInterval) -> TimeInterval {
        MeasureTiming.snapToNearestBeat(
            max(0, time),
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
    }

    var clipLaneActions: ClipLaneActions {
        ClipLaneActions(
            press: { clipID, trackID, modifiers in
                let wasSelected = clipSelection.press(clipID, extending: modifiers.shift)
                pendingShiftDeselectID = wasSelected ? clipID : nil
            },
            click: { clipID, modifiers, time in
                // A click is an insertion, so the range selection does not stay underneath it.
                editSelection = nil
                if modifiers.option {
                    splitSelectedClips(at: time)
                } else {
                    clipSelection.click(
                        clipID,
                        extending: modifiers.shift,
                        removing: pendingShiftDeselectID == clipID
                    )
                }
                pendingShiftDeselectID = nil
            },
            drag: updateClipDrag,
            endDrag: commitClipDrag,
            marquee: updateRangeDrag,
            endMarquee: {
                // Mouse-up keeps editSelection. The range stays in place.
            },
            clickBlank: { trackID, time in
                editSelection = nil
                clipSelection.deselectAll()
                placeInsertion(on: trackID, at: time)
            },
            locate: { trackID, time in
                placeInsertion(on: trackID, at: time)
            },
            menu: performClipMenuAction
        )
    }

    /// Raises or lowers every selected clip by `delta` decibels.
    private func nudgeSelectedClipGain(by delta: Double) {
        let ids = clipSelection.clipIDs
        guard !ids.isEmpty else { return }
        var edited = timeline.clips
        ClipEditing.nudgeGain(clipIDs: ids, by: delta, in: &edited)
        guard edited != timeline.clips else { return }
        commitTimelineEdit(delta > 0 ? "Nudge Clip Gain Up" : "Nudge Clip Gain Down") { timeline in
            timeline.clips = edited
        }
    }

    /// Opens the gain prompt for the current selection. Mixed gains start with an empty field.
    private func beginAdjustGain() {
        let clips = selectedClips
        guard let first = clips.first else { return }
        let shared = clips.allSatisfy { abs($0.gainDB - first.gainDB) < 0.05 } ? first.gainDB : nil
        activeSheet = .clipGain(ClipGainPromptRequest(decibels: shared, clipCount: clips.count))
    }

    func applyClipGain(_ decibels: Double) {
        let ids = clipSelection.clipIDs
        guard !ids.isEmpty else {
            activeSheet = nil
            return
        }
        var edited = timeline.clips
        ClipEditing.setGain(clipIDs: ids, decibels: decibels, in: &edited)
        activeSheet = nil
        guard edited != timeline.clips else { return }
        commitTimelineEdit("Adjust Gain") { timeline in
            timeline.clips = edited
        }
    }

    /// Snaps the reference clip's moved edge to the beat grid and applies that change to the whole selection.
    private func updateClipDrag(_ request: ClipDragRequest) {
        pendingShiftDeselectID = nil
        switch request {
        case .move(let reference, let rawDelta, let copy):
            let earliest = selectedClips.map(\.timelineStartSeconds).min() ?? reference.timelineStartSeconds
            let delta = snappedToBeat(reference.timelineStartSeconds + rawDelta) - reference.timelineStartSeconds
            clipDrag = .move(delta: max(delta, -earliest), copy: copy)
        case .trim(let reference, let edge, let rawTime):
            let edgeTime = edge == .leading ? reference.timelineStartSeconds : reference.timelineEndSeconds
            clipDrag = .trim(edge: edge, delta: snappedToBeat(rawTime) - edgeTime)
        }
    }

    private func commitClipDrag() {
        guard let drag = clipDrag else { return }
        clipDrag = nil
        let ids = clipSelection.clipIDs
        switch drag {
        case .move(let delta, let copy):
            guard abs(delta) > ClipEditing.tolerance else { return }
            if copy {
                commitTimelineEdit("Copy Clips") { timeline in
                    clipSelection = ClipSelection(ClipEditing.copy(clipIDs: ids, by: delta, in: &timeline.clips))
                }
            } else {
                commitTimelineEdit("Move Clips") { timeline in
                    ClipEditing.move(clipIDs: ids, by: delta, in: &timeline.clips)
                }
            }
        case .trim(let edge, let delta):
            guard abs(delta) > ClipEditing.tolerance else { return }
            let durations = Dictionary(uniqueKeysWithValues: song.sortedTracks.map { ($0.id, viewModel.fileDuration(for: $0)) })
            commitTimelineEdit("Trim Clips") { timeline in
                ClipEditing.trim(
                    clipIDs: ids,
                    edge: edge,
                    by: delta,
                    sourceDuration: { durations[$0] ?? 0 },
                    in: &timeline.clips
                )
            }
        }
        clipSelection.retain(existing: timeline.clips)
    }

    /// A context-menu action on a clip outside the selection first makes it the only selected clip.
    /// Split uses the edit selection, so it decides that itself.
    private func performClipMenuAction(_ action: ClipMenuAction, clipID: UUID) {
        let clipWasSelected = clipSelection.contains(clipID)
        if action != .split, !clipWasSelected {
            clipSelection = ClipSelection([clipID])
        }
        switch action {
        case .split: splitAtEditSelection(clickedClipID: clipID, clipWasSelected: clipWasSelected)
        case .join: joinSelectedClips()
        case .duplicate: duplicateSelectedClips()
        case .adjustGain: beginAdjustGain()
        case .delete: removeClipSelection()
        }
    }

    /// Rows run MIDI first, then audio. The drag selects each clip the range overlaps on those rows.
    private func updateRangeDrag(from start: CGPoint, to current: CGPoint, modifiers _: PointerModifiers) {
        let ids = displayedTrackIDs
        guard !ids.isEmpty else { return }
        let frames = laneFrames
        func row(at y: CGFloat) -> Int {
            frames.rowIndex(at: y)
        }
        let lowRow = min(row(at: start.y), row(at: current.y))
        let highRow = max(row(at: start.y), row(at: current.y))
        let startTime = snappedToBeat(time(atX: start.x))
        let endTime = snappedToBeat(time(atX: current.x))
        editSelection = ClipRangeDrag(
            start: min(startTime, endTime),
            end: max(startTime, endTime),
            firstRow: lowRow,
            lastRow: highRow
        )
        pendingShiftDeselectID = nil
        clipDrag = nil
        let trackIDs = Set(ids[lowRow...highRow])
        selectedTrackIDs = trackIDs
        clipSelection = ClipSelection(
            ClipSelection.clipIDs(
                in: timeline.clips,
                trackIDs: trackIDs,
                from: startTime,
                to: endTime
            )
        )
    }

    func time(atX x: CGFloat) -> TimeInterval {
        TimelineLayout.time(at: x, duration: timelineDuration, contentWidth: timelineContentWidth)
    }
}
