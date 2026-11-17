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
        return range(around: offset, viewportWidth: viewportWidth)
    }

    /// The viewport at `offset` with `marginScreens` either side.
    static func range(around offset: CGFloat, viewportWidth: CGFloat) -> ClosedRange<CGFloat> {
        let origin = max(0, offset)
        let margin = viewportWidth * marginScreens
        return max(0, origin - margin)...(origin + viewportWidth + margin)
    }
}

/// A view drawn in viewport coordinates that must move in the same frame as the scroll.
@MainActor
protocol TimelineOffsetFollowing: AnyObject {
    func timelineOffsetDidChange(_ offset: CGFloat)
}

/// A view drawn outside SwiftUI that shows the rulers at the zoom on screen during a live zoom.
@MainActor
protocol TimelineLiveZoomFollowing: TimelineOffsetFollowing {
    /// `scale` is the zoom on screen over the zoom SwiftUI has laid out, or `nil` once it has
    /// caught up.
    func liveZoomDidChange(scale: CGFloat?, offset: CGFloat)
}

/// Scroll position for the rulers, the playhead and the lane canvas.
/// The lane tree does not read `offset`, so a horizontal tick does not rebuild it.
///
/// During a live zoom, the lanes and the rulers keep the zoom SwiftUI laid them out at: the
/// lanes are stretched, and an AppKit ruler covers the SwiftUI one. Laying the rulers out again
/// on every step cost more than a frame, so only views outside SwiftUI follow the live zoom.
@MainActor
@Observable
final class TimelineHorizontalScrollModel {
    var offset: CGFloat = 0
    /// Told about every offset change directly, outside SwiftUI's update cycle.
    @ObservationIgnored weak var laneCanvas: (any TimelineOffsetFollowing)?
    @ObservationIgnored weak var gridOverlay: (any TimelineOffsetFollowing)?
    @ObservationIgnored weak var liveRuler: (any TimelineLiveZoomFollowing)?
    /// The slice the lanes and rulers lay content out for, in their own coordinates. During a
    /// live zoom those keep the zoom they were laid out at, so this range rarely moves: zooming
    /// in keeps the viewport inside it.
    private(set) var paintedRange: ClosedRange<CGFloat> = 0...8_192
    /// Zoom on screen during a live zoom, before the editor has laid it out. `nil` otherwise.
    private(set) var liveZoom: CGFloat?
    /// The live zoom over the zoom SwiftUI has laid out. 1 outside a live zoom.
    @ObservationIgnored private var layoutScale: CGFloat = 1
    private var viewportWidth: CGFloat = 0

    /// `width`, laid out at `zoom`, at the zoom on screen.
    func liveWidth(_ width: CGFloat, laidOutAt zoom: CGFloat) -> CGFloat {
        guard let liveZoom, zoom > 0 else { return width }
        return width * liveZoom / zoom
    }

    /// Sets the zoom on screen during a live zoom, or `nil` when the editor has caught up.
    func setLiveZoom(_ zoom: CGFloat?, laidOutAt laidOutZoom: CGFloat) {
        if liveZoom != zoom {
            liveZoom = zoom
        }
        layoutScale = zoom.map { laidOutZoom > 0 ? $0 / laidOutZoom : 1 } ?? 1
        liveRuler?.liveZoomDidChange(scale: zoom == nil ? nil : layoutScale, offset: offset)
        // Mid-zoom, the offset for this zoom arrives next, so the range moves with it rather
        // than once here from the old offset. Once SwiftUI has laid the zoom out, it moves now.
        if layoutScale == 1 {
            updatePaintedRange()
        }
    }

    func setViewportWidth(_ width: CGFloat) {
        let width = max(0, width)
        guard abs(viewportWidth - width) > 0.5 else { return }
        viewportWidth = width
        guard width > 0 else { return }
        paintedRange = TimelineHorizontalPaint.range(
            around: offset / layoutScale,
            viewportWidth: width / layoutScale
        )
    }

    func setOffset(_ newOffset: CGFloat) {
        if offset != newOffset {
            offset = newOffset
            laneCanvas?.timelineOffsetDidChange(newOffset)
            gridOverlay?.timelineOffsetDidChange(newOffset)
            liveRuler?.timelineOffsetDidChange(newOffset)
        }
        updatePaintedRange()
    }

    private func updatePaintedRange() {
        let updated = TimelineHorizontalPaint.range(
            keeping: paintedRange,
            offset: offset / layoutScale,
            viewportWidth: viewportWidth / layoutScale
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
