import SwiftUI

/// One audio lane as the lane canvas draws it.
struct TimelineCanvasLane: Equatable {
    let originY: CGFloat
    let height: CGFloat
    let fileURL: URL
    let bodyColor: Color
    let clips: [TimelineCanvasClip]
}

/// The parts of a clip the lane canvas draws.
struct TimelineCanvasClip: Equatable {
    let id: UUID
    let timelineStart: TimeInterval
    let timelineEnd: TimeInterval
    let sourceStart: TimeInterval
    let sourceDuration: TimeInterval
    let linearGain: Float

    init(_ clip: TrackClip) {
        id = clip.id
        timelineStart = clip.timelineStartSeconds
        timelineEnd = clip.timelineEndSeconds
        sourceStart = clip.sourceStartSeconds
        sourceDuration = clip.sourceDuration
        linearGain = clip.linearGain
    }
}

/// Clip bodies and waveforms of the audio lanes, drawn behind the scrolling lane chrome.
///
/// The canvas is as wide as the viewport and does not scroll. On macOS the horizontal scroll
/// view owns it; on iOS `TimelineLaneCanvasLayer` places it and the scroll model moves it.
struct TimelineLaneCanvas: Equatable {
    let lanes: [TimelineCanvasLane]
    let duration: TimeInterval
    let contentWidth: CGFloat
    let loadsWaveforms: Bool

    func scene(in environment: EnvironmentValues) -> TimelineLanePainter.Scene {
        TimelineLanePainter.Scene(
            lanes: lanes.map { lane in
                TimelineLanePainter.Lane(
                    originY: lane.originY,
                    height: lane.height,
                    fileURL: lane.fileURL,
                    bodyColor: lane.bodyColor.resolve(in: environment).cgColor,
                    clips: lane.clips
                )
            },
            duration: max(duration, 0.001),
            contentWidth: contentWidth,
            backgroundColor: Color.dawTimelineBackground.resolve(in: environment).cgColor,
            loadsWaveforms: loadsWaveforms
        )
    }
}

#if os(iOS)
/// The lane canvas behind the horizontal `ScrollView`, following the scroll model's offset.
struct TimelineLaneCanvasLayer: UIViewRepresentable {
    let canvas: TimelineLaneCanvas
    let scrollModel: TimelineHorizontalScrollModel

    func makeUIView(context: Context) -> TimelineLaneCanvasView {
        TimelineLaneCanvasView(frame: .zero)
    }

    func updateUIView(_ view: TimelineLaneCanvasView, context: Context) {
        view.follow(scrollModel)
        view.update(canvas.scene(in: context.environment))
    }
}
#endif
