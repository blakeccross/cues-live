import SwiftUI

/// Minutes-and-seconds ruler, pinned at the top of the timeline above the meter lane.
/// Ticks rise from the bottom edge; labeled times sit to the right of a tall tick and shorter
/// ticks fill the gaps.
struct TimelineTimeRulerView: View {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let height: CGFloat

    private static let labelTop: CGFloat = 3

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var effectiveDisplayWidth: CGFloat {
        max(contentWidth, displayWidth)
    }

    private var pixelsPerSecond: CGFloat {
        contentWidth / CGFloat(safeDuration)
    }

    var body: some View {
        Canvas { context, size in
            let scale = TimeRulerScale(pixelsPerSecond: pixelsPerSecond)
            let mark = GraphicsContext.Shading.color(AppColors.Timeline.timeRulerTick)
            let end = extendedMaximumTime
            guard scale.minor > 0, end >= 0 else { return }

            let subdivisions = max(1, Int((scale.major / scale.minor).rounded()))
            let stepCount = Int((end / scale.minor).rounded(.down))
            let minorTickHeight = min(4, size.height)
            let majorTickHeight = min(max(9, size.height * 0.46), size.height)

            var minorPath = Path()
            var majorPath = Path()
            for step in 0...stepCount {
                let time = Double(step) * scale.minor
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                guard x <= size.width + 1 else { break }
                let isMajor = step % subdivisions == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height))
                tick.addLine(to: CGPoint(x: x, y: size.height - (isMajor ? majorTickHeight : minorTickHeight)))
                if isMajor {
                    majorPath.addPath(tick)
                } else {
                    minorPath.addPath(tick)
                }
            }

            context.stroke(minorPath, with: mark, lineWidth: 1)
            context.stroke(majorPath, with: mark, lineWidth: 1)

            for step in stride(from: 0, through: stepCount, by: subdivisions) {
                let time = Double(step) * scale.minor
                let x = TimelineLayout.xPosition(
                    for: time,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                guard x <= size.width - 8 else { break }
                let label = context.resolve(
                    Text(Self.formatRulerTime(time, showsFraction: scale.major < 1))
                        .font(AppTypography.Compact.timecode)
                        .foregroundStyle(.secondary)
                )
                context.draw(label, at: CGPoint(x: x + 4, y: Self.labelTop), anchor: .topLeading)
            }
        }
        .frame(width: effectiveDisplayWidth, height: height)
        .background(AppColors.Timeline.stickyRulerBackground)
        .allowsHitTesting(false)
    }

    private var extendedMaximumTime: TimeInterval {
        guard contentWidth > 0, effectiveDisplayWidth > contentWidth else { return safeDuration }
        return safeDuration * TimeInterval(effectiveDisplayWidth / contentWidth)
    }

    private static func formatRulerTime(_ value: TimeInterval, showsFraction: Bool) -> String {
        let clamped = max(0, value)
        let minutes = Int(clamped) / 60
        let seconds = clamped - Double(minutes * 60)
        if showsFraction {
            return String(format: "%d:%04.1f", minutes, seconds)
        }
        let wholeSeconds = Int((seconds + 0.000_1).rounded(.down))
        return String(format: "%d:%02d", minutes, wholeSeconds)
    }
}

/// Labeled spacing stays wide enough to read; unlabeled ticks subdivide it.
private struct TimeRulerScale {
    var major: TimeInterval
    var minor: TimeInterval

    init(pixelsPerSecond: CGFloat) {
        let pps = max(pixelsPerSecond, 0.001)
        let majors: [TimeInterval] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let raw = Double(140 / pps)
        major = majors.first(where: { $0 >= raw - 0.000_1 }) ?? 600
        let candidate = Self.preferredMinor(for: major)
        minor = CGFloat(candidate) * pps >= 8 ? candidate : major
    }

    private static func preferredMinor(for major: TimeInterval) -> TimeInterval {
        switch major {
        case 0.1: return 0.02
        case 0.2: return 0.05
        case 0.5: return 0.1
        case 1: return 0.2
        case 2: return 0.5
        case 5: return 1
        case 10: return 2
        case 15: return 5
        case 30: return 5
        case 60: return 10
        case 120: return 30
        case 300: return 60
        default: return 120
        }
    }
}
