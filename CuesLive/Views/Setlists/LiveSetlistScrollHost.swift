import SwiftUI

/// Native horizontal scroll view for the setlist waveform strip.
///
/// The song lanes' labels and gestures are SwiftUI inside an AppKit or UIKit scroll view, so a
/// scroll is a scroll-view offset change and nothing in SwiftUI is laid out. Their waveforms are
/// drawn by a viewport-wide canvas behind them. A display link reads the playhead, scrolls to
/// follow it, moves the playhead line and redraws the canvas, all in the same frame.
/// `LiveSetlistScrollModel` decides where the strip should be.
@MainActor
struct LiveSetlistScrollHost<Content: View> {
    let model: LiveSetlistScrollModel
    let currentIndex: Int
    let playheadTime: () -> TimeInterval
    let isPlaying: () -> Bool
    /// Playhead while stopped. `nil` while playing.
    let idlePlayheadTime: TimeInterval?
    /// Playback indices of the songs in the strip. Lanes for any other index are dropped.
    let laneIndices: Set<Int>
    /// What the canvas behind the lanes draws.
    let canvas: LiveSetlistLaneCanvas
    /// Touch pinch, read by a recognizer on the scroll view so it runs alongside panning.
    /// macOS pinches with a SwiftUI gesture inside the content instead.
    var onPinchChanged: (CGFloat) -> Void = { _ in }
    var onPinchEnded: () -> Void = {}
    /// Command- or Option-scroll on macOS, with the factor to multiply the zoom by.
    var onWheelZoom: (CGFloat) -> Void = { _ in }
    @ViewBuilder let content: () -> Content

    private func syncModel() {
        model.currentTime = playheadTime
        model.isPlaying = isPlaying
        model.idleTime = idlePlayheadTime
        model.setCurrentIndex(currentIndex)
        model.retainLanes(at: laneIndices)
    }

    /// The content runs in its own hosting view, which starts with an empty environment.
    private func rootView(in environment: EnvironmentValues) -> AnyView {
        AnyView(content().environment(\.self, environment))
    }
}

#if os(macOS)
extension LiveSetlistScrollHost: NSViewRepresentable {
    func makeNSView(context: Context) -> LiveSetlistNSScrollView {
        LiveSetlistNSScrollView(model: model)
    }

    func updateNSView(_ view: LiveSetlistNSScrollView, context: Context) {
        syncModel()
        view.onWheelZoom = onWheelZoom
        view.update(rootView: rootView(in: context.environment), scene: canvas.scene(in: context.environment))
    }
}
#else
extension LiveSetlistScrollHost: UIViewRepresentable {
    func makeUIView(context: Context) -> LiveSetlistUIScrollView {
        LiveSetlistUIScrollView(model: model)
    }

    func updateUIView(_ view: LiveSetlistUIScrollView, context: Context) {
        syncModel()
        view.onPinchChanged = onPinchChanged
        view.onPinchEnded = onPinchEnded
        view.update(rootView: rootView(in: context.environment), scene: canvas.scene(in: context.environment))
    }
}
#endif
