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

    /// Audio lanes in display order, below the MIDI lanes. Tracks without a file draw nothing.
    private var laneCanvasLanes: [TimelineCanvasLane] {
        let frames = laneFrames
        let clipsByTrack = Dictionary(grouping: previewClips, by: \.trackID)
        return song.sortedTracks.enumerated().compactMap { index, track in
            let rowIndex = midiTracks.count + index
            guard frames.rows.indices.contains(rowIndex),
                  let fileURL = FileStore.trackURL(for: song, track: track) else {
                return nil
            }
            let row = frames.rows[rowIndex]
            return TimelineCanvasLane(
                originY: row.originY,
                height: row.height,
                fileURL: fileURL,
                bodyColor: TrackGroupPalette.colors(forPaletteKey: track.group?.paletteKey).body,
                clips: (clipsByTrack[track.id] ?? []).map(TimelineCanvasClip.init)
            )
        }
    }
}
