import Observation
import SwiftUI

/// Extra viewports of lane chrome and grid kept laid out around the scroll position.
/// Scrolling inside that slice does not rebuild the lanes.
enum TimelineHorizontalPaint {
    /// One screen either side keeps a sliced canvas, three viewports wide, under the
    /// 16,384-pixel texture limit on a Retina display.
    static let marginScreens: CGFloat = 1

    static func range(
        keeping painted: ClosedRange<CGFloat>,
        offset: CGFloat,
        viewportWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        guard viewportWidth > 0 else { return painted }
        let origin = max(0, offset)
        let visible = origin...(origin + viewportWidth)
        // Repaint while a margin of already-drawn waveform is still on screen.
        let lead = viewportWidth * 0.5
        let comfortLower = painted.lowerBound + lead
        let comfortUpper = painted.upperBound - lead
        if comfortLower <= visible.lowerBound, comfortUpper >= visible.upperBound {
            return painted
        }
        let margin = viewportWidth * marginScreens
        return max(0, origin - margin)...(origin + viewportWidth + margin)
    }
}

/// A view drawn in viewport coordinates that must move in the same frame as the scroll.
@MainActor
protocol TimelineOffsetFollowing: AnyObject {
    func timelineOffsetDidChange(_ offset: CGFloat)
}

/// Scroll position for the rulers, the playhead and the lane canvas.
/// The lane tree does not read `offset`, so a horizontal tick does not rebuild it.
@MainActor
@Observable
final class TimelineHorizontalScrollModel {
    var offset: CGFloat = 0
    /// Told about every offset change directly, outside SwiftUI's update cycle.
    @ObservationIgnored weak var laneCanvas: (any TimelineOffsetFollowing)?
    private(set) var paintedRange: ClosedRange<CGFloat> = 0...8_192
    private var viewportWidth: CGFloat = 0

    func setViewportWidth(_ width: CGFloat) {
        let width = max(0, width)
        guard abs(viewportWidth - width) > 0.5 else { return }
        viewportWidth = width
        guard width > 0 else { return }
        let margin = width * TimelineHorizontalPaint.marginScreens
        let origin = max(0, offset)
        paintedRange = max(0, origin - margin)...(origin + width + margin)
    }

    func setOffset(_ newOffset: CGFloat) {
        if offset != newOffset {
            offset = newOffset
            laneCanvas?.timelineOffsetDidChange(newOffset)
        }
        let updated = TimelineHorizontalPaint.range(
            keeping: paintedRange,
            offset: newOffset,
            viewportWidth: viewportWidth
        )
        if updated != paintedRange {
            paintedRange = updated
        }
    }
}

private struct TimelineScrollModelKey: EnvironmentKey {
    static let defaultValue: TimelineHorizontalScrollModel? = nil
}

extension EnvironmentValues {
    /// Horizontal scroll model for the editor. Lane chrome reads `paintedRange` only.
    var timelineScrollModel: TimelineHorizontalScrollModel? {
        get { self[TimelineScrollModelKey.self] }
        set { self[TimelineScrollModelKey.self] = newValue }
    }
}
