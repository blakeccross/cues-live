import SwiftUI

/// Read-only strip below the waveform showing one MIDI device's cue points as
/// small dots along the timeline — the setlist view's counterpart to the song
/// editor's fully-interactive `MIDILaneView`.
struct LiveMIDIEventLaneView: View {
    let contentWidth: CGFloat
    let timelineDuration: TimeInterval
    let deviceName: String
    let events: [MIDIEvent]

    private static let dotSize: CGFloat = 6
    /// Keeps the device tag just inside the lane's rounded corner.
    private static let tagOffset = CGSize(width: 3, height: 1)

    private var safeDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(AppColors.Live.midiLaneBackground)

            ForEach(events) { event in
                Circle()
                    .fill(AppColors.Live.midiEventDot)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .position(
                        x: TimelineLayout.xPosition(
                            for: event.timelineSeconds,
                            duration: safeDuration,
                            contentWidth: contentWidth
                        ),
                        y: LiveSetlistWaveformMetrics.midiLaneRowHeight / 2
                    )
            }

            Text(deviceName.uppercased())
                .font(AppTypography.Compact.laneTag)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .appTag(AppColors.Live.tagBackground)
                .padding(.leading, Self.tagOffset.width)
                .padding(.top, Self.tagOffset.height)
        }
        .frame(width: contentWidth, height: LiveSetlistWaveformMetrics.midiLaneRowHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .allowsHitTesting(false)
    }
}
