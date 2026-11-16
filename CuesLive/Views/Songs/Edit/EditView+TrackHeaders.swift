import SwiftUI

extension EditView {
    var trackHeaderList: some View {
        LazyVStack(spacing: TimelineLayout.laneSpacing) {
            if let video = song.videoTrack {
                videoTrackHeader(video)
            }

            ForEach(midiTracks, id: \.id) { track in
                MIDITrackHeaderView(
                    track: track,
                    laneHeight: TrackLaneHeight.resolved(track.laneHeight),
                    isSelected: selectedTrackIDs.contains(track.id),
                    onSelect: { modifiers in
                        selectedTrackIDs = TrackSelection.click(
                            id: track.id,
                            in: selectedTrackIDs,
                            order: displayedTrackIDs,
                            modifiers: modifiers
                        )
                    },
                    onConfigChange: commitMIDIConfig,
                    onSendTest: { sendMIDITest(for: track) },
                    onEditDevice: { editDevice(for: track) },
                    onDelete: { deleteMIDITrack(track) },
                    onResize: { resizeLane(track.id, by: $0) },
                    onResizeEnded: finishLaneResize
                )
            }

            ForEach(song.sortedTracks, id: \.id) { track in
                TrackLaneHeaderView(
                    track: track,
                    laneHeight: TrackLaneHeight.resolved(track.laneHeight),
                    isSelected: selectedTrackIDs.contains(track.id),
                    groups: trackGroups,
                    onSelect: { modifiers in
                        selectedTrackIDs = TrackSelection.click(
                            id: track.id,
                            in: selectedTrackIDs,
                            order: displayedTrackIDs,
                            modifiers: modifiers
                        )
                    },
                    onMixChange: {
                        performUndoableChange("Mix Track") {
                            viewModel.updateMix(for: track, context: modelContext)
                        }
                    },
                    onGroupChange: {
                        performUndoableChange("Assign Group") {
                            viewModel.updateGroup(for: track, context: modelContext)
                        }
                    },
                    onManageGroups: {
                        activeSheet = .groupEditor
                    },
                    onRename: {
                        beginRenameTrack(track)
                    },
                    onDelete: {
                        deleteAudioTrack(track)
                    },
                    onResize: { resizeLane(track.id, by: $0) },
                    onResizeEnded: finishLaneResize
                )
            }
        }
        .frame(width: TimelineLayout.trackHeaderWidth)
        .background(AppColors.Timeline.trackHeaderColumnBackground)
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            guard audioEngine.isPlaying || audioEngine.hasVisibleMeterLevel else { return }
            audioEngine.refreshGroupMeters()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.Timeline.divider)
                .frame(width: 1)
        }
    }
}
