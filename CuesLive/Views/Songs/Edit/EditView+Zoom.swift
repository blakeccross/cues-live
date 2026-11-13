import SwiftUI

extension EditView {
    /// How far one Zoom In or Zoom Out command moves the timeline.
    private static let zoomCommandStep: CGFloat = 1.5

    var timelineMinZoom: CGFloat {
        TimelineLayout.minZoom(duration: timelineDuration, viewportWidth: timelineViewportWidth)
    }

    var timelineZoomActions: TimelineZoomActions {
        TimelineZoomActions(
            canZoomIn: timelineZoom < TimelineLayout.maxZoom,
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
            timelineZoom = min(TimelineLayout.maxZoom, max(minZoom, timelineZoom))
        }
    }

    /// Multiplies the zoom by `scale`, within the fit-to-window and maximum levels.
    func zoomTimeline(by scale: CGFloat) {
        setTimelineZoom(timelineZoom * scale)
    }

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

    private func setTimelineZoom(_ proposed: CGFloat) {
        timelineZoom = min(TimelineLayout.maxZoom, max(timelineMinZoom, proposed))
    }
}
