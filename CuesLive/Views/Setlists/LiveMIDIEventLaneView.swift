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

    private var safeDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(Color.white.opacity(0.06))

            ForEach(events) { event in
                Circle()
                    .fill(Color.white.opacity(0.85))
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
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(AppColors.surfaceElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(.leading, 3)
                .padding(.top, 1)
        }
        .frame(width: contentWidth, height: LiveSetlistWaveformMetrics.midiLaneRowHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .allowsHitTesting(false)
    }
}
