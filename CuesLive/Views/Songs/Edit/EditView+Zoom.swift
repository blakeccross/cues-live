import SwiftUI

extension EditView {
    /// How far one Zoom In or Zoom Out command moves the timeline.
    private static let zoomCommandStep: CGFloat = 1.5

    var timelineMinZoom: CGFloat {
        TimelineLayout.minZoom(duration: timelineDuration, viewportWidth: timelineViewportWidth)
    }

    var timelineMaxZoom: CGFloat {
        max(timelineMinZoom, TimelineLayout.maxZoom)
    }

    var timelineZoomActions: TimelineZoomActions {
        TimelineZoomActions(
            canZoomIn: timelineZoom < timelineMaxZoom,
            canZoomOut: timelineZoom > timelineMinZoom,
            zoomIn: { zoomTimeline(by: Self.zoomCommandStep) },
            zoomOut: { zoomTimeline(by: 1 / Self.zoomCommandStep) }
        )
    }

    func clampTimelineZoom() {
        guard timelineViewportWidth > 0 else { return }
        let minZoom = timelineMinZoom
        if !hasSetInitialTimelineZoom {
            timelineZoom = minZoom
            hasSetInitialTimelineZoom = true
        } else {
            timelineZoom = min(timelineMaxZoom, max(minZoom, timelineZoom))
        }
    }

    /// Multiplies the zoom by `scale`, within the fit-to-window and maximum levels.
    func zoomTimeline(by scale: CGFloat) {
        setTimelineZoom(timelineZoom * scale)
    }

    #if os(iOS)
    /// A pinch over the timeline. On macOS the horizontal scroll view zooms pinches itself.
    var timelinePinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStartZoom == nil {
                    pinchStartZoom = timelineZoom
                }
                guard let pinchStartZoom else { return }
                setTimelineZoom(pinchStartZoom * scale)
            }
            .onEnded { _ in
                pinchStartZoom = nil
            }
    }
    #endif

    /// Sets the zoom, within the fit-to-window and maximum levels.
    func setTimelineZoom(_ proposed: CGFloat) {
        timelineZoom = min(timelineMaxZoom, max(timelineMinZoom, proposed))
    }
}
