import SwiftUI

/// The setlist's marker for the current song: a filled accent dot while cued, and bouncing
/// equalizer bars while it plays.
struct NowPlayingIndicator: View {
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dotDiameter: CGFloat = 8
    private static let barCount = 4
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2
    private static let barMaxHeight: CGFloat = 14
    private static let barMinFraction = 0.2
    /// Each bar mixes two sine waves at its own rates so the bars never fall into step.
    private static let barRates: [(Double, Double)] = [(5.1, 2.3), (6.7, 3.1), (4.3, 1.7), (7.3, 2.9)]

    var body: some View {
        Group {
            if isPlaying {
                bars
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(AppAnimation.springSnappy, value: isPlaying)
        .accessibilityElement()
        .accessibilityLabel(isPlaying ? "Now playing" : "Cued")
    }

    private var bars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: Self.barWidth / 2)
                        .fill(AppColors.accent)
                        .frame(
                            width: Self.barWidth,
                            height: Self.barMaxHeight * heightFraction(bar: index, time: reduceMotion ? 0 : time)
                        )
                }
            }
            .frame(height: Self.barMaxHeight, alignment: .bottom)
        }
    }

    private func heightFraction(bar index: Int, time: TimeInterval) -> Double {
        let (fast, slow) = Self.barRates[index % Self.barRates.count]
        let phase = Double(index) * 1.3
        let wave = (sin(time * fast + phase) + sin(time * slow + phase * 2)) / 4 + 0.5
        return Self.barMinFraction + (1 - Self.barMinFraction) * wave
    }
}
