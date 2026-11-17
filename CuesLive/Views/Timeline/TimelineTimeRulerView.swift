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

    /// Set by the editor's ruler follower. The canvas then covers only the painted slice, so
    /// a deep zoom does not draw, or allocate, the whole song's width.
    @Environment(\.timelineScrollModel) private var scrollModel

    /// Content x range the canvas occupies: the painted slice when scrolled, else everything.
    private var paintedSlice: ClosedRange<CGFloat> {
        let width = effectiveDisplayWidth
        guard let painted = scrollModel?.paintedRange else { return 0...width }
        let lower = max(0, painted.lowerBound)
        let upper = min(width, painted.upperBound)
        return upper > lower ? lower...upper : 0...0
    }

    var body: some View {
        let slice = paintedSlice
        Canvas { context, size in
            context.translateBy(x: -slice.lowerBound, y: 0)
            drawTicks(in: &context, height: size.height, slice: slice)
        }
        .frame(width: slice.upperBound - slice.lowerBound, height: height)
        .offset(x: slice.lowerBound)
        .frame(width: effectiveDisplayWidth, height: height, alignment: .leading)
        .background(AppColors.Timeline.stickyRulerBackground)
        .allowsHitTesting(false)
    }

    /// Ticks and labels whose x falls in `slice`, in content coordinates.
    private func drawTicks(in context: inout GraphicsContext, height: CGFloat, slice: ClosedRange<CGFloat>) {
        let scale = TimelineTimeRulerScale(pixelsPerSecond: pixelsPerSecond)
        guard scale.minor > 0, pixelsPerSecond > 0 else { return }
        let mark = GraphicsContext.Shading.color(AppColors.Timeline.timeRulerTick)
        let subdivisions = max(1, Int((scale.major / scale.minor).rounded()))
        let lastStep = Int((extendedMaximumTime / scale.minor).rounded(.down))
        // Start on a labeled tick left of the slice, so a label straddling its edge still draws.
        let sliceStartStep = Int((Double(slice.lowerBound / pixelsPerSecond) / scale.minor).rounded(.down))
        let firstStep = max(0, sliceStartStep - sliceStartStep % subdivisions - subdivisions)
        let endStep = min(lastStep, Int((Double(slice.upperBound / pixelsPerSecond) / scale.minor).rounded(.up)))
        guard firstStep <= endStep else { return }

        let minorTickHeight = min(4, height)
        let majorTickHeight = min(max(9, height * 0.46), height)
        var minorPath = Path()
        var majorPath = Path()
        for step in firstStep...endStep {
            let x = xPosition(forStep: step, scale: scale)
            guard x <= effectiveDisplayWidth + 1 else { break }
            if step % subdivisions == 0 {
                majorPath.addPath(tick(at: x, height: height, length: majorTickHeight))
            } else {
                minorPath.addPath(tick(at: x, height: height, length: minorTickHeight))
            }
        }
        context.stroke(minorPath, with: mark, lineWidth: 1)
        context.stroke(majorPath, with: mark, lineWidth: 1)

        let labelLimit = effectiveDisplayWidth - 8
        for step in stride(from: firstStep, through: endStep, by: subdivisions) {
            let x = xPosition(forStep: step, scale: scale)
            guard x <= labelLimit else { break }
            let label = context.resolve(
                Text(scale.label(for: Double(step) * scale.minor))
                    .font(AppTypography.Compact.timecode)
                    .foregroundStyle(.secondary)
            )
            context.draw(label, at: CGPoint(x: x + 4, y: Self.labelTop), anchor: .topLeading)
        }
    }

    private func xPosition(forStep step: Int, scale: TimelineTimeRulerScale) -> CGFloat {
        TimelineLayout.xPosition(for: Double(step) * scale.minor, duration: safeDuration, contentWidth: contentWidth)
    }

    private func tick(at x: CGFloat, height: CGFloat, length: CGFloat) -> Path {
        var tick = Path()
        tick.move(to: CGPoint(x: x, y: height))
        tick.addLine(to: CGPoint(x: x, y: height - length))
        return tick
    }

    private var extendedMaximumTime: TimeInterval {
        guard contentWidth > 0, effectiveDisplayWidth > contentWidth else { return safeDuration }
        return safeDuration * TimeInterval(effectiveDisplayWidth / contentWidth)
    }
}
