import CoreGraphics
import Foundation

/// Draws the measure grid over the editor's lanes: bar lines, then beats and their halves once
/// each is far enough apart to read. Lines stop at clip headers so the name bars stay solid.
/// Section lines and the wash outside the in and out points go over the grid.
///
/// It draws in viewport coordinates from the scroll offset, like `TimelineLanePainter`, so a
/// scroll or a live zoom redraws it without laying out any SwiftUI.
@MainActor
final class TimelineGridPainter {
    /// A clip header the lines skip.
    struct Header: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let originY: CGFloat
    }

    struct Scene: Equatable {
        var duration: TimeInterval = 1
        var contentWidth: CGFloat = 1
        var tempoChanges: [TempoChange] = []
        var timeSignatureChanges: [TimeSignatureChange] = []
        var headers: [Header] = []
        var barColor = CGColor(gray: 0, alpha: 0.2)
        var beatColor = CGColor(gray: 0, alpha: 0.12)
        var subdivisionColor = CGColor(gray: 0, alpha: 0.08)
        var sectionTimes: [TimeInterval] = []
        /// The in and out points, or `nil` to leave the lanes unshaded.
        var playRange: ClosedRange<TimeInterval>?
        var sectionLineColor = CGColor(gray: 0, alpha: 0.5)
        var outsidePlayRangeColor = CGColor(gray: 0, alpha: 0.3)
        var playRangeEdgeShadowColor = CGColor(gray: 0, alpha: 0.3)
    }

    private(set) var scene = Scene()
    /// Horizontal scroll offset in content points.
    var offset: CGFloat = 0
    /// Content width during a live zoom, before SwiftUI has laid out the new zoom.
    var liveContentWidth: CGFloat?
    /// The in and out points while a flag is dragged.
    var previewRange: ClosedRange<TimeInterval>?

    /// Returns `true` when the scene changed and needs drawing.
    func update(_ scene: Scene) -> Bool {
        guard scene != self.scene else { return false }
        self.scene = scene
        return true
    }

    /// Draws `rect`, in view coordinates.
    func draw(in context: CGContext, rect: CGRect) {
        let width = liveContentWidth ?? scene.contentWidth
        guard width > 0 else { return }
        drawGrid(in: context, rect: rect, width: width)
        drawMarkers(in: context, rect: rect, width: width)
    }

    private func drawGrid(in context: CGContext, rect: CGRect, width: CGFloat) {
        guard !scene.tempoChanges.isEmpty else { return }
        let duration = scene.duration
        let lower = max(0, Double((rect.minX + offset - 1) / width) * duration)
        let upper = Double((rect.maxX + offset + 1) / width) * duration
        guard upper > lower else { return }

        let bands = scene.headers.map { header in
            CGRect(
                x: x(for: header.start, width: width),
                y: header.originY,
                width: x(for: header.end, width: width) - x(for: header.start, width: width),
                height: TimelineLayout.clipHeaderHeight
            )
        }
        let fine = fineGrid(width: width, in: lower...upper)
        let bars = MeasureTiming.visibleMeasureBoundaries(
            duration: duration,
            tempoChanges: scene.tempoChanges,
            contentWidth: width,
            timeSignatureChanges: scene.timeSignatureChanges,
            maximumTime: max(duration, upper),
            visibleTimeRange: lower...upper
        )
        stroke(fine.subdivisions, color: scene.subdivisionColor, width: width, bands: bands, rect: rect, context: context)
        stroke(fine.beats, color: scene.beatColor, width: width, bands: bands, rect: rect, context: context)
        stroke(bars, color: scene.barColor, width: width, bands: bands, rect: rect, context: context)
    }

    func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: scene.duration, contentWidth: width) - offset
    }

    /// Beats, then eighths, once each level is far enough apart to read.
    private func fineGrid(width: CGFloat, in range: ClosedRange<TimeInterval>) -> MeasureTiming.BeatGridTimes {
        let fastest = scene.tempoChanges.map(\.bpm).filter { $0 > 0 }.max() ?? 0
        let detail = MeasureTiming.LaneGridDetail.detail(
            pixelsPerSecond: width / CGFloat(scene.duration),
            fastestBPM: fastest
        )
        guard detail.showsBeats else { return MeasureTiming.BeatGridTimes(beats: [], subdivisions: []) }
        let grid = MeasureTiming.beatGridTimes(
            duration: scene.duration,
            tempoChanges: scene.tempoChanges,
            timeSignatureChanges: scene.timeSignatureChanges,
            visibleTimeRange: range
        )
        return MeasureTiming.BeatGridTimes(
            beats: grid.beats,
            subdivisions: detail.showsSubdivisions ? grid.subdivisions : []
        )
    }

    private func stroke(
        _ times: [TimeInterval],
        color: CGColor,
        width: CGFloat,
        bands: [CGRect],
        rect: CGRect,
        context: CGContext
    ) {
        guard !times.isEmpty else { return }
        let path = CGMutablePath()
        for time in times {
            let x = x(for: time, width: width)
            guard x >= rect.minX - 1, x <= rect.maxX + 1 else { continue }
            let gaps = MeasureGridSpans.gaps(at: x, in: bands)
            for (start, end) in MeasureGridSpans.verticalSegments(from: rect.minY, to: rect.maxY, skipping: gaps) {
                path.move(to: CGPoint(x: x, y: start))
                path.addLine(to: CGPoint(x: x, y: end))
            }
        }
        context.setStrokeColor(color)
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()
    }
}
