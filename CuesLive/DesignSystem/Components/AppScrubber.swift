import SwiftUI

/// A playback scrubber in the style of Music: a thin capsule that thickens and brightens while
/// dragged, with elapsed and remaining time beneath it. Dragging anywhere along it jumps there.
struct AppScrubber: View {
    @Binding var value: TimeInterval
    let duration: TimeInterval
    /// Called with `true` when a drag begins and `false` when it ends.
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    private static let trackHeight: CGFloat = 4
    private static let activeTrackHeight: CGFloat = 10
    /// Height of the touch area around the track.
    private static let hitHeight: CGFloat = 24
    /// Seconds one VoiceOver swipe moves.
    private static let accessibilityStep: TimeInterval = 5

    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(value / duration, 0), 1))
    }

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            track
            HStack {
                Text(Self.timeText(value))
                Spacer()
                Text("-" + Self.timeText(max(0, duration - value)))
            }
            .font(AppTypography.caption2Emphasized)
            .monospacedDigit()
            .foregroundStyle(isDragging ? AppColors.textPrimary : AppColors.textTertiary)
        }
        .animation(AppAnimation.springSnappy, value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(Self.timeText(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(duration, value + Self.accessibilityStep)
            case .decrement:
                value = max(0, value - Self.accessibilityStep)
            @unknown default:
                break
            }
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.scrubberTrack)
                Capsule()
                    .fill(isDragging ? AppColors.textPrimary : AppColors.scrubberFill)
                    .frame(width: geometry.size.width * fraction)
            }
            .frame(height: isDragging ? Self.activeTrackHeight : Self.trackHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geometry.size.width))
        }
        .frame(height: Self.hitHeight)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }
                guard width > 0 else { return }
                let proposed = TimeInterval(gesture.location.x / width) * duration
                value = min(max(0, proposed), duration)
            }
            .onEnded { _ in
                isDragging = false
                onEditingChanged(false)
            }
    }

    private static func timeText(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
