import SwiftUI

extension EditView {
    /// Clip bodies and waveforms of the audio lanes, drawn behind the lane chrome.
    var trackLaneCanvas: TimelineLaneCanvas {
        TimelineLaneCanvas(
            lanes: laneCanvasLanes,
            duration: timelineDuration,
            contentWidth: timelineContentWidth,
            loadsWaveforms: viewModel.isLoaded
        )
    }

    /// Audio lanes in display order, below the video and MIDI lanes. Tracks without a file draw nothing.
    private var laneCanvasLanes: [TimelineCanvasLane] {
        let rowByID = laneRowsByTrackID
        let clipsByTrack = Dictionary(grouping: previewClips, by: \.trackID)
        return song.sortedTracks.compactMap { track in
            guard let row = rowByID[track.id],
                  let fileURL = FileStore.trackURL(for: song, track: track) else {
                return nil
            }
            return TimelineCanvasLane(
                originY: row.originY,
                height: row.height,
                fileURL: fileURL,
                bodyColor: TrackGroupPalette.colors(forPaletteKey: track.group?.paletteKey).body,
                clips: (clipsByTrack[track.id] ?? []).map { clip in
                    TimelineCanvasClip(clip, showsFadeCurves: showsFadeCurves(on: clip))
                }
            )
        }
    }

    /// Under the pointer, or while one of its fades is dragged. Touch has no hover, so there
    /// the curves are always drawn.
    private func showsFadeCurves(on clip: TrackClip) -> Bool {
        #if os(macOS)
        if case .fade(let clipID, _, _) = clipDrag, clipID == clip.id { return true }
        return hoveredClipID == clip.id
        #else
        true
        #endif
    }

    /// Each shown track's lane frame, from a single layout pass. Rows are found by track ID, not
    /// by index, so a lane added since the frames were computed cannot point past their end.
    var laneRowsByTrackID: [UUID: TrackLaneFrames.Row] {
        Dictionary(zip(displayedTrackIDs, laneFrames.rows), uniquingKeysWith: { first, _ in first })
    }

    /// The rows a range selection covers that still exist. The selection keeps row numbers from
    /// before a lane was added or removed.
    func selectionRows(_ drag: ClipRangeDrag, in frames: TrackLaneFrames) -> [Int] {
        let lastRow = min(drag.lastRow, frames.rows.count - 1)
        guard drag.firstRow >= 0, drag.firstRow <= lastRow else { return [] }
        return Array(drag.firstRow...lastRow)
    }
}
