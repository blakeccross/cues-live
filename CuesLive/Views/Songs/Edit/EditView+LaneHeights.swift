import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditView {
    var trackHeightActions: TrackHeightActions {
        TrackHeightActions(
            canStep: !selectedTrackIDs.isEmpty,
            increase: { stepTrackHeight(taller: true, option: false, shift: false) },
            decrease: { stepTrackHeight(taller: false, option: false, shift: false) }
        )
    }

    var trackAreaHeight: CGFloat {
        laneFrames.totalHeight
    }

    /// Rows in `displayedTrackIDs` order. Heights are read straight from the tracks: looking each
    /// ID up again is quadratic in SwiftData reads, and this runs several times per zoom step.
    var laneFrames: TrackLaneFrames {
        var stored = song.videoTrack.map { [$0.laneHeight] } ?? []
        stored += midiTracks.map(\.laneHeight)
        stored += song.sortedTracks.map(\.laneHeight)
        return TrackLaneFrames(heights: stored.map { TrackLaneHeight.resolved($0) })
    }

    func laneHeight(for id: UUID) -> CGFloat {
        if let track = song.tracks.first(where: { $0.id == id }) {
            return TrackLaneHeight.resolved(track.laneHeight)
        }
        if let track = song.midiTracks.first(where: { $0.id == id }) {
            return TrackLaneHeight.resolved(track.laneHeight)
        }
        if let video = song.videoTrack, video.id == id {
            return TrackLaneHeight.resolved(video.laneHeight)
        }
        return TrackLaneHeight.medium
    }

    private func setLaneHeight(_ height: CGFloat, id: UUID) {
        let stored = Double(height)
        if let track = song.tracks.first(where: { $0.id == id }) {
            if track.laneHeight != stored {
                track.laneHeight = stored
            }
            return
        }
        if let track = song.midiTracks.first(where: { $0.id == id }) {
            if track.laneHeight != stored {
                track.laneHeight = stored
            }
            return
        }
        if let video = song.videoTrack, video.id == id, video.laneHeight != stored {
            video.laneHeight = stored
        }
    }

    /// Live resize. Command drags freely. Option resizes every track, Option-Shift the selected ones.
    func resizeLane(_ trackID: UUID, by delta: CGFloat) {
        if laneResize?.trackID != trackID {
            finishLaneResize()
            laneResize = LaneResizeDrag(
                trackID: trackID,
                startHeight: laneHeight(for: trackID),
                before: captureSnapshot()
            )
        }
        guard let drag = laneResize else { return }
        let modifiers = PointerModifiers.current
        let want = drag.startHeight + delta
        let height = modifiers.command ? TrackLaneHeight.free(want) : TrackLaneHeight.snapped(want)
        let targets = TrackLaneHeight.targets(
            owned: [trackID],
            shown: displayedTrackIDs,
            selected: selectedTrackIDs,
            option: modifiers.option,
            shift: modifiers.shift
        )
        for id in targets {
            setLaneHeight(height, id: id)
        }
    }

    func finishLaneResize() {
        guard let drag = laneResize else { return }
        laneResize = nil
        let after = captureSnapshot()
        guard drag.before != after else { return }
        undoController.registerChange(
            actionName: "Track Height",
            before: drag.before,
            after: after,
            apply: { snapshot in
                applySnapshot(snapshot)
            }
        )
        persistProjectState()
    }

    func stepTrackHeight(taller: Bool, option: Bool, shift: Bool) {
        let targets = TrackLaneHeight.targets(
            owned: selectedTrackIDs,
            shown: displayedTrackIDs,
            selected: selectedTrackIDs,
            option: option,
            shift: shift
        )
        let updates = targets.compactMap { id -> (UUID, CGFloat)? in
            let next = TrackLaneHeight.step(laneHeight(for: id), taller: taller)
            guard next != laneHeight(for: id) else { return nil }
            return (id, next)
        }
        guard !updates.isEmpty else { return }
        performUndoableChange("Track Height") {
            for (id, height) in updates {
                setLaneHeight(height, id: id)
            }
            persistProjectState()
        }
    }
}
