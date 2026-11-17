import SwiftUI

/// One song drawn by `LiveSetlistLanePainter` outside the setlist scroll view, for the overlap
/// editor. `songFrame` places the song's whole in-to-out lane in this view's coordinates; only the
/// part inside the view is drawn.
struct OverlapLaneCanvas {
    let snapshot: LiveSongWaveformSnapshot
    let songFrame: CGRect
    /// View x of the preview playhead. Everything left of it draws as played.
    let playheadX: CGFloat

    @MainActor
    fileprivate func refresh(_ view: LiveSetlistLaneCanvasView, environment: EnvironmentValues) {
        let canvas = LiveSetlistLaneCanvas(
            songs: [LiveSetlistLaneCanvas.Song(index: 0, snapshot: snapshot, isCurrent: true)]
        )
        // Sections keep their plain gray markers; the editor has no current song to highlight.
        var scene = canvas.scene(in: environment)
        scene.playedMarkerColor = scene.markerColor
        scene.unplayedMarkerColor = scene.markerColor
        view.update(scene)
        view.refresh(LiveSetlistLanePainter.Layout(origin: .zero, lanes: [0: songFrame], playheadX: playheadX))
    }
}

#if os(macOS)
extension OverlapLaneCanvas: NSViewRepresentable {
    func makeNSView(context: Context) -> LiveSetlistLaneCanvasView {
        LiveSetlistLaneCanvasView(frame: .zero)
    }

    func updateNSView(_ view: LiveSetlistLaneCanvasView, context: Context) {
        refresh(view, environment: context.environment)
    }
}
#else
extension OverlapLaneCanvas: UIViewRepresentable {
    func makeUIView(context: Context) -> LiveSetlistLaneCanvasView {
        LiveSetlistLaneCanvasView(frame: .zero)
    }

    func updateUIView(_ view: LiveSetlistLaneCanvasView, context: Context) {
        refresh(view, environment: context.environment)
    }
}
#endif
