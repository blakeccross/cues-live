import SwiftUI

/// Wash over the lane viewport before the in point and after the out point. This view, not the
/// container, reads the scroll offset and the drag preview, so either one redraws only the wash.
struct TimelinePlayRangeShade: View {
    var model: TimelineHorizontalScrollModel
    var preview: TimelinePlayRangePreview
    let range: ClosedRange<TimeInterval>
    let duration: TimeInterval
    let contentWidth: CGFloat
    let viewportWidth: CGFloat

    var body: some View {
        let shown = preview.range ?? range
        let offset = model.offset
        Canvas { context, size in
            guard size.width > 0, size.height > 0, contentWidth > 0 else { return }
            let inX = xPosition(for: shown.lowerBound) - offset
            let outX = xPosition(for: shown.upperBound) - offset
            let wash = GraphicsContext.Shading.color(AppColors.Timeline.outsidePlayRange)
            if inX > 0 {
                context.fill(Path(CGRect(x: 0, y: 0, width: min(inX, size.width), height: size.height)), with: wash)
            }
            if outX < size.width {
                let start = max(0, outX)
                context.fill(Path(CGRect(x: start, y: 0, width: size.width - start, height: size.height)), with: wash)
                let shadow = CGRect(x: outX, y: 0, width: TimelinePlayRangeEdgeShadow.width, height: size.height)
                context.fill(Path(shadow), with: TimelinePlayRangeEdgeShadow.shading(across: shadow))
            }
        }
        .frame(width: viewportWidth)
        .allowsHitTesting(false)
    }

    private func xPosition(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: duration, contentWidth: contentWidth)
    }
}
