import SwiftUI

/// One song's lane in the overlap editor, drawn like the setlist strip: section ribbon, measure
/// ticks, and the summed waveform split at the preview playhead, labelled with the song's name.
struct OverlapWaveformLaneView: View {
    let title: String
    let snapshot: LiveSongWaveformSnapshot
    /// The song's own time at the lane's leading edge. May fall outside the song when it starts or
    /// ends inside the lane.
    let startTime: TimeInterval
    let pointsPerSecond: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// The song's own time at the playhead. Times before or after the song pin to its ends.
    let playheadTime: TimeInterval

    /// The song's whole in-to-out lane, in this view's coordinates.
    private var songFrame: CGRect {
        let window = snapshot.window
        return CGRect(
            x: -CGFloat(startTime - window.start) * pointsPerSecond,
            y: 0,
            width: CGFloat(window.duration) * pointsPerSecond,
            height: height
        )
    }

    var body: some View {
        let frame = songFrame

        OverlapLaneCanvas(snapshot: snapshot, songFrame: frame, playheadX: playheadX(in: frame))
            .overlay(alignment: .topLeading) {
                LiveSectionRibbonLabels(
                    window: snapshot.window,
                    sections: snapshot.sections,
                    loopSectionIDs: snapshot.loopSectionIDs,
                    contentWidth: frame.width,
                    height: height
                )
                .offset(x: frame.minX)
            }
            .overlay(alignment: .bottomLeading) {
                Text(title)
                    .font(AppTypography.caption2Emphasized)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .appTag(AppColors.Live.tagBackground)
                    .padding(AppSpacing.xs)
                    // Rides the song's leading edge until it scrolls off, then holds at the lane's.
                    .offset(x: max(0, frame.minX))
            }
            .frame(width: max(width, 1), height: height)
            .clipped()
    }

    private func playheadX(in frame: CGRect) -> CGFloat {
        frame.minX + snapshot.window.x(for: playheadTime, width: frame.width)
    }
}
