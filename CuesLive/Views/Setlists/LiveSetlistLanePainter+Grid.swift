import CoreGraphics
import Foundation

/// Section bands and the measure grid behind a song's waveform.
extension LiveSetlistLanePainter {
    func drawBands(_ song: Song, in lane: CGRect, shown: CGRect, context: CGContext) {
        for band in song.bands {
            let startX = lane.minX + x(for: band.start, song: song, lane: lane)
            let endX = lane.minX + x(for: band.end, song: song, lane: lane)
            guard endX >= shown.minX, startX <= shown.maxX else { continue }
            let bandRect = CGRect(x: startX, y: lane.minY, width: max(0, endX - startX), height: lane.height)

            context.setFillColor(band.isCued && scene.cueFlashPhase ? band.cuedColor : band.color)
            context.fill(bandRect.intersection(shown))
            if band.isCued {
                context.setStrokeColor(scene.accentColor.copy(alpha: scene.cueFlashPhase ? 1 : 0.35) ?? scene.accentColor)
                context.setLineWidth(2)
                context.stroke(bandRect)
            }
            context.setFillColor(scene.separatorColor)
            context.fill(CGRect(x: startX, y: lane.minY, width: 0.5, height: lane.height).intersection(shown))
        }
    }

    func drawMeasureGrid(_ song: Song, in lane: CGRect, shown: CGRect, context: CGContext) {
        guard !song.tempoChanges.isEmpty, song.duration > 0, lane.width > 0 else { return }

        let padding: CGFloat = 40
        let visibleStart = time(at: shown.minX - lane.minX - padding, song: song, lane: lane)
        let visibleEnd = time(at: shown.maxX - lane.minX + padding, song: song, lane: lane)
        let visible = visibleStart...max(visibleStart, visibleEnd)
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: song.duration,
            tempoChanges: song.tempoChanges,
            contentWidth: lane.width,
            timeSignatureChanges: song.timeSignatureChanges,
            minimumPixelSpacing: song.duration > 30 * 60 ? 24 : 10,
            visibleTimeRange: visible
        )
        let spacing = pixelsPerBeat(song, laneWidth: lane.width)
        let showsBeats = song.duration <= LiveSetlistWaveformMetrics.beatGridMaximumDuration
            && spacing >= LiveSetlistWaveformMetrics.minimumBeatTickSpacing
        let showsSubdivisions = showsBeats
            && spacing / 2 >= LiveSetlistWaveformMetrics.minimumSubdivisionTickSpacing
        let grid = showsBeats
            ? MeasureTiming.beatGridTimes(
                duration: song.duration,
                tempoChanges: song.tempoChanges,
                timeSignatureChanges: song.timeSignatureChanges,
                visibleTimeRange: visible
            )
            : MeasureTiming.BeatGridTimes(beats: [], subdivisions: [])

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
        for time in times {
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
        return CGFloat(beatDuration) * laneWidth / CGFloat(song.duration)
    }

    private func x(for time: TimeInterval, song: Song, lane: CGRect) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: song.duration, contentWidth: lane.width)
    }

    private func time(at x: CGFloat, song: Song, lane: CGRect) -> TimeInterval {
        TimelineLayout.time(at: x, duration: song.duration, contentWidth: lane.width)
    }
}
