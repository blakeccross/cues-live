import SwiftUI

extension LiveSetlistWaveformScrollView {
    /// VoiceOver's increment and decrement step.
    private static let zoomAdjustmentStep: CGFloat = 0.25
    /// How far one Zoom In or Zoom Out command moves the strip.
    private static let zoomCommandStep: CGFloat = 1.25

    var horizontalZoomActions: TimelineZoomActions {
        TimelineZoomActions(
            canZoomIn: horizontalZoom < LiveSetlistWaveformMetrics.maximumHorizontalZoom,
            canZoomOut: horizontalZoom > LiveSetlistWaveformMetrics.minimumHorizontalZoom,
            zoomIn: { zoomHorizontally(by: Self.zoomCommandStep) },
            zoomOut: { zoomHorizontally(by: 1 / Self.zoomCommandStep) }
        )
    }

    #if os(macOS)
    var horizontalPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged(pinchChanged)
            .onEnded { _ in pinchEnded() }
    }
    #endif

    func pinchChanged(_ scale: CGFloat) {
        if pinchStartZoom == nil {
            pinchStartZoom = horizontalZoom
            scrollModel.anchorPlayheadForZoom()
        }
        guard let pinchStartZoom else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            horizontalZoom = LiveSetlistWaveformMetrics.clampedHorizontalZoom(pinchStartZoom * scale)
        }
    }

    func pinchEnded() {
        pinchStartZoom = nil
        persistHorizontalZoom()
    }

    /// Multiplies the zoom by `scale`, keeping the content under the playhead in place.
    func zoomHorizontally(by scale: CGFloat) {
        setHorizontalZoom(horizontalZoom * scale)
    }

    func adjustHorizontalZoom(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            setHorizontalZoom(horizontalZoom + Self.zoomAdjustmentStep)
        case .decrement:
            setHorizontalZoom(horizontalZoom - Self.zoomAdjustmentStep)
        @unknown default:
            break
        }
    }

    private func setHorizontalZoom(_ proposed: CGFloat) {
        let newZoom = LiveSetlistWaveformMetrics.clampedHorizontalZoom(proposed)
        guard newZoom != horizontalZoom else { return }
        scrollModel.anchorPlayheadForZoom()
        horizontalZoom = newZoom
        persistHorizontalZoom()
    }

    private func persistHorizontalZoom() {
        storedHorizontalZoom = LiveSetlistWaveformMetrics.storageValue(forZoom: horizontalZoom)
    }
}
