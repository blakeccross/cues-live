import CoreGraphics
import Foundation

/// The section ribbon above a song's waveform, and the measure grid over it.
extension LiveSetlistLanePainter {
    private static let cueOutlineWidth: CGFloat = 1.5

    /// Draws one flush marker per section across `ribbon`. In the current song, everything left of
    /// the playhead takes the played color and everything right of it the unplayed color; other
    /// songs use the plain marker color.
    func drawRibbon(_ song: Song, in ribbon: CGRect, lane: CGRect, shown: CGRect, context: CGContext) {
        guard ribbon.height > 0 else { return }
        let playheadX = song.isCurrent ? layout.playheadX.map { $0 - layout.origin.x } : nil
        for band in song.bands {
            let startX = lane.minX + x(for: band.start, song: song, lane: lane)
            let endX = lane.minX + x(for: band.end, song: song, lane: lane)
            guard endX >= shown.minX, startX <= shown.maxX else { continue }
            let marker = CGRect(x: startX, y: ribbon.minY, width: max(0, endX - startX), height: ribbon.height)

            let (played, ahead) = marker.divided(
                atDistance: playheadX.map { $0 - startX } ?? 0,
                from: .minXEdge
            )
            context.setFillColor(scene.playedMarkerColor)
            context.fill(played.intersection(shown))
            context.setFillColor(song.isCurrent ? scene.unplayedMarkerColor : scene.markerColor)
            context.fill(ahead.intersection(shown))
            if band.isCued {
                let inset = Self.cueOutlineWidth
                context.setStrokeColor(CGColor(gray: 1, alpha: scene.cueFlashPhase ? 1 : 0.35))
                context.setLineWidth(Self.cueOutlineWidth)
                context.stroke(marker.insetBy(dx: inset, dy: inset))
            }
            guard startX > lane.minX else { continue }
            // A seam between neighbouring markers, continued as a hairline through the waveform.
            context.setFillColor(scene.backgroundColor)
            context.fill(CGRect(x: startX - 0.5, y: ribbon.minY, width: 1, height: ribbon.height).intersection(shown))
            context.setFillColor(scene.separatorColor)
            context.fill(CGRect(x: startX, y: ribbon.maxY, width: 0.5, height: lane.maxY - ribbon.maxY).intersection(shown))
        }
    }

    func drawMeasureGrid(_ song: Song, in lane: CGRect, shown: CGRect, context: CGContext) {
        guard !song.tempoChanges.isEmpty, lane.width > 0 else { return }
        let window = song.window
        // The grid is laid out from time zero, which sits before the lane when the in point is
        // later. This width keeps the lane's pixels per second across that whole span.
        let timelineWidth = lane.width * CGFloat(window.end / window.duration)

        let padding: CGFloat = 40
        let visibleStart = time(at: shown.minX - lane.minX - padding, song: song, lane: lane)
        let visibleEnd = time(at: shown.maxX - lane.minX + padding, song: song, lane: lane)
        let visible = visibleStart...max(visibleStart, visibleEnd)
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: window.end,
            tempoChanges: song.tempoChanges,
            contentWidth: timelineWidth,
            timeSignatureChanges: song.timeSignatureChanges,
            minimumPixelSpacing: window.duration > 30 * 60 ? 24 : 10,
            visibleTimeRange: visible
        )
        let spacing = pixelsPerBeat(song, laneWidth: lane.width)
        let showsBeats = window.duration <= LiveSetlistWaveformMetrics.beatGridMaximumDuration
            && spacing >= LiveSetlistWaveformMetrics.minimumBeatTickSpacing
        let showsSubdivisions = showsBeats
            && spacing / 2 >= LiveSetlistWaveformMetrics.minimumSubdivisionTickSpacing
        let grid = showsBeats
            ? MeasureTiming.beatGridTimes(
                duration: window.end,
                tempoChanges: song.tempoChanges,
                timeSignatureChanges: song.timeSignatureChanges,
                visibleTimeRange: visible
            )
            : MeasureTiming.BeatGridTimes(beats: [], subdivisions: [])

        // Drawn over the waveform with a difference blend, so a tick lightens the background and
        // darkens the waveform it crosses, staying visible on both.
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(.difference)
        let inset = min(Self.gridInset, lane.height / 2)
        let lines = GridLines(
            top: lane.minY + inset,
            height: max(0, lane.height - inset * 2),
            shown: shown
        )
        if showsSubdivisions {
            stroke(grid.subdivisions, song: song, lane: lane, lines: lines,
                   alpha: LiveSetlistWaveformMetrics.subdivisionTickOpacity, context: context)
        }
        if showsBeats {
            stroke(grid.beats, song: song, lane: lane, lines: lines,
                   alpha: LiveSetlistWaveformMetrics.beatTickOpacity, context: context)
        }
        stroke(boundaries, song: song, lane: lane, lines: lines,
               alpha: LiveSetlistWaveformMetrics.downbeatTickOpacity, context: context)
    }

    private struct GridLines {
        let top: CGFloat
        let height: CGFloat
        let shown: CGRect
    }

    private func stroke(
        _ times: [TimeInterval],
        song: Song,
        lane: CGRect,
        lines: GridLines,
        alpha: CGFloat,
        context: CGContext
    ) {
        context.setFillColor(CGColor(gray: 1, alpha: alpha))
        // Ticks outside the window would pin to the lane's ends.
        for time in times where time >= song.window.start && time <= song.window.end {
            let x = lane.minX + x(for: time, song: song, lane: lane)
            guard x >= lines.shown.minX - 1, x <= lines.shown.maxX + 1 else { continue }
            let snapped = ((x - 0.5) * scale).rounded() / scale
            context.fill(CGRect(x: snapped, y: lines.top, width: 1, height: lines.height))
        }
    }

    private func pixelsPerBeat(_ song: Song, laneWidth: CGFloat) -> CGFloat {
        let bpm = MeasureTiming.bpmForMeasure(1, tempoChanges: song.tempoChanges)
        let signature = MeasureTiming.numeratorDenominatorForMeasure(1, changes: song.timeSignatureChanges)
        let beatsInMeasure = MeasureTiming.beatsPerMeasure(
            numerator: signature.numerator,
            denominator: signature.denominator
        )
        guard beatsInMeasure > 0 else { return 0 }
        let beatDuration = MeasureTiming.measureDuration(
            bpm: bpm,
            numerator: signature.numerator,
            denominator: signature.denominator
        ) / beatsInMeasure
        return CGFloat(beatDuration) * laneWidth / CGFloat(song.window.duration)
    }

    private func x(for time: TimeInterval, song: Song, lane: CGRect) -> CGFloat {
        song.window.x(for: time, width: lane.width)
    }

    private func time(at x: CGFloat, song: Song, lane: CGRect) -> TimeInterval {
        song.window.time(at: x, width: lane.width)
    }
}
