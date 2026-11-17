import SwiftUI

/// One audio lane as the lane canvas draws it.
struct TimelineCanvasLane: Equatable {
    let originY: CGFloat
    let height: CGFloat
    let fileURL: URL
    /// Track name, drawn in each clip's header.
    let name: String
    let bodyColor: Color
    let headerColor: Color
    let selectedHeaderColor: Color
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
    let fadeIn: ClipFade
    let fadeOut: ClipFade
    /// The fade curves are drawn as lines. The painter also draws them on the hovered clip, and
    /// always draws the shading under them.
    let showsFadeCurves: Bool
    let isSelected: Bool

    init(_ clip: TrackClip, showsFadeCurves: Bool, isSelected: Bool) {
        id = clip.id
        timelineStart = clip.timelineStartSeconds
        timelineEnd = clip.timelineEndSeconds
        sourceStart = clip.sourceStartSeconds
        sourceDuration = clip.sourceDuration
        linearGain = clip.linearGain
        fadeIn = clip.fadeIn
        fadeOut = clip.fadeOut
        self.showsFadeCurves = showsFadeCurves
        self.isSelected = isSelected
    }

    /// Gain of the clip's waveform when it is drawn `width` points wide from content x `startX`.
    func columnGain(startX: CGFloat, width: CGFloat) -> WaveformColumnGain {
        guard fadeIn.isActive || fadeOut.isActive else { return WaveformColumnGain(level: linearGain) }
        return WaveformColumnGain(
            level: linearGain,
            fades: WaveformColumnGain.Fades(
                startX: startX,
                width: width,
                duration: timelineEnd - timelineStart,
                fadeIn: fadeIn,
                fadeOut: fadeOut
            )
        )
    }
}

/// What the audio lanes look like: clip bodies, headers, borders and waveforms drawn behind the
/// scrolling lane chrome, and the measure grid drawn over it.
///
/// Both surfaces are as wide as the viewport and do not scroll. On macOS the horizontal scroll
/// view owns them; on iOS `TimelineLaneCanvasLayer` places them and the scroll model moves them.
struct TimelineLaneCanvas {
    let lanes: [TimelineCanvasLane]
    let duration: TimeInterval
    let contentWidth: CGFloat
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let sectionTimes: [TimeInterval]
    /// The in and out points as committed. The grid shades from `playRangePreview` mid-drag.
    let playRange: ClosedRange<TimeInterval>
    let playRangePreview: TimelinePlayRangePreview
    let loadsWaveforms: Bool
    /// The clip under the pointer. On macOS the canvas follows it directly, outside SwiftUI updates.
    let hover: TimelineClipHoverModel

    func scene(in environment: EnvironmentValues) -> TimelineLanePainter.Scene {
        TimelineLanePainter.Scene(
            lanes: lanes.map { lane in
                TimelineLanePainter.Lane(
                    originY: lane.originY,
                    height: lane.height,
                    fileURL: lane.fileURL,
                    name: lane.name,
                    bodyColor: lane.bodyColor.resolve(in: environment).cgColor,
                    headerColor: lane.headerColor.resolve(in: environment).cgColor,
                    selectedHeaderColor: lane.selectedHeaderColor.resolve(in: environment).cgColor,
                    borderColor: lane.headerColor.opacity(Self.borderOpacity).resolve(in: environment).cgColor,
                    clips: lane.clips
                )
            },
            duration: max(duration, 0.001),
            contentWidth: contentWidth,
            backgroundColor: AppColors.Timeline.background.resolve(in: environment).cgColor,
            headerTextColor: AppColors.Timeline.clipHeaderText.resolve(in: environment).cgColor,
            selectedHeaderTextColor: AppColors.Timeline.clipHeaderTextSelected.resolve(in: environment).cgColor,
            loadsWaveforms: loadsWaveforms
        )
    }

    func gridScene(in environment: EnvironmentValues) -> TimelineGridPainter.Scene {
        TimelineGridPainter.Scene(
            duration: max(duration, 0.001),
            contentWidth: contentWidth,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            headers: lanes.flatMap { lane in
                lane.clips.map { TimelineGridPainter.Header(start: $0.timelineStart, end: $0.timelineEnd, originY: lane.originY) }
            },
            barColor: AppColors.Timeline.barTick.resolve(in: environment).cgColor,
            beatColor: AppColors.Timeline.beatTick.resolve(in: environment).cgColor,
            subdivisionColor: AppColors.Timeline.subdivisionTick.resolve(in: environment).cgColor,
            sectionTimes: sectionTimes,
            playRange: playRange,
            sectionLineColor: AppColors.Timeline.sectionMarkerLine.resolve(in: environment).cgColor,
            outsidePlayRangeColor: AppColors.Timeline.outsidePlayRange.resolve(in: environment).cgColor,
            playRangeEdgeShadowColor: AppColors.Timeline.playRangeEdgeShadow.resolve(in: environment).cgColor
        )
    }

    /// An unselected clip's left, right and bottom edges, against its header color.
    private static let borderOpacity = 0.6
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
