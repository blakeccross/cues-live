#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

/// AppKit `CATiledLayer` drawer for long setlist waveform lanes.
/// SwiftUI `Canvas` over multi‑tens‑of‑thousands‑pt content re-layouts on every
/// pan frame; tiled layers paint only exposed tiles.
struct LiveSongWaveformScrollBacking: NSViewRepresentable {
    var contentWidth: CGFloat
    var timelineDuration: TimeInterval
    var mins: [Float]
    var maxes: [Float]
    var sections: [SongSection]
    var tempoChanges: [TempoChange]
    var timeSignatureChanges: [TimeSignatureChange]
    var showsMeasureGrid: Bool
    var cuedSectionID: UUID?
    var cueFlashPhase: Bool
    var playheadTime: TimeInterval?
    var showsPlayheadSplit: Bool
    var isLoading: Bool

    private static let unplayedOpacity = LiveSetlistWaveformMetrics.waveformUnplayedOpacity
    private static let playedOpacity = LiveSetlistWaveformMetrics.waveformPlayedOpacity

    func makeNSView(context: Context) -> LiveSongWaveformScrollBackingView {
        let view = LiveSongWaveformScrollBackingView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: LiveSongWaveformScrollBackingView, context: Context) {
        let previous = nsView.model
        apply(to: nsView)
        let next = nsView.model

        if previous.structurallyEquals(next) {
            if previous.playheadTime != next.playheadTime {
                nsView.invalidatePlayhead(from: previous.playheadTime, to: next.playheadTime)
            }
            return
        }

        nsView.invalidateWaveform()
    }

    private func apply(to view: LiveSongWaveformScrollBackingView) {
        view.model = LiveSongWaveformScrollBackingView.Model(
            contentWidth: contentWidth,
            timelineDuration: max(timelineDuration, 0.001),
            mins: mins,
            maxes: maxes,
            sections: sections,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            showsMeasureGrid: showsMeasureGrid,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            playheadTime: playheadTime,
            showsPlayheadSplit: showsPlayheadSplit,
            unplayedOpacity: Self.unplayedOpacity,
            playedOpacity: Self.playedOpacity,
            isLoading: isLoading
        )
    }
}

final class LiveSongWaveformScrollBackingView: NSView {
    struct Model: Equatable {
        var contentWidth: CGFloat = 1
        var timelineDuration: TimeInterval = 1
        var mins: [Float] = []
        var maxes: [Float] = []
        var sections: [SongSection] = []
        var tempoChanges: [TempoChange] = []
        var timeSignatureChanges: [TimeSignatureChange] = []
        var showsMeasureGrid = true
        var cuedSectionID: UUID?
        var cueFlashPhase = false
        var playheadTime: TimeInterval?
        var showsPlayheadSplit = false
        var unplayedOpacity: CGFloat = LiveSetlistWaveformMetrics.waveformUnplayedOpacity
        var playedOpacity: CGFloat = LiveSetlistWaveformMetrics.waveformPlayedOpacity
        var isLoading = false

        func structurallyEquals(_ other: Model) -> Bool {
            contentWidth == other.contentWidth
                && timelineDuration == other.timelineDuration
                && mins == other.mins
                && maxes == other.maxes
                && sections == other.sections
                && tempoChanges == other.tempoChanges
                && timeSignatureChanges == other.timeSignatureChanges
                && showsMeasureGrid == other.showsMeasureGrid
                && cuedSectionID == other.cuedSectionID
                && cueFlashPhase == other.cueFlashPhase
                && showsPlayheadSplit == other.showsPlayheadSplit
                && unplayedOpacity == other.unplayedOpacity
                && playedOpacity == other.playedOpacity
                && isLoading == other.isLoading
        }
    }

    var model = Model()

    private static let gridInset: CGFloat = 8
    private static let playheadInvalidatePadding: CGFloat = 12

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { false }

    override func makeBackingLayer() -> CALayer {
        let layer = CATiledLayer()
        layer.tileSize = CGSize(width: 512, height: 256)
        layer.levelsOfDetail = 1
        layer.levelsOfDetailBias = 0
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Lets AppKit stretch the existing tiles while the enclosing VSplitView
        // divider is being dragged (bars/grid scale proportionally with height,
        // so the stretch reads correctly) instead of us forcing a full
        // CATiledLayer re-rasterization on every pixel of the drag, which reads
        // as flicker/tearing. `viewDidEndLiveResize` below catches the settled
        // height up to a sharp render once the drag ends.
        layerContentsRedrawPolicy = .beforeViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Gestures live on the SwiftUI overlay; never steal scroll/seek hits.
        nil
    }

    func invalidateWaveform() {
        layer?.setNeedsDisplay()
        needsDisplay = true
    }

    /// Redraw only the tiles spanning the playhead move so scroll stays smooth.
    func invalidatePlayhead(from oldTime: TimeInterval?, to newTime: TimeInterval?) {
        let times = [oldTime, newTime].compactMap { $0 }
        guard !times.isEmpty else {
            invalidateWaveform()
            return
        }

        let xs = times.map { xPosition(for: min($0, model.timelineDuration)) }
        let minX = max(0, (xs.min() ?? 0) - Self.playheadInvalidatePadding)
        let maxX = min(bounds.width, (xs.max() ?? 0) + Self.playheadInvalidatePadding)
        let dirty = NSRect(x: minX, y: 0, width: max(1, maxX - minX), height: bounds.height)
        layer?.setNeedsDisplay(dirty)
        setNeedsDisplay(dirty)
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = dirtyRect.intersection(bounds)
        guard rect.width > 0, rect.height > 0 else { return }

        NSColor(Color.liveVoiceMemosBackground).setFill()
        rect.fill()

        drawSectionBackgrounds(in: rect)
        if model.showsMeasureGrid {
            drawMeasureGrid(in: rect)
        }
        drawWaveformBars(in: rect)
    }

    private func xPosition(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(
            for: time,
            duration: model.timelineDuration,
            contentWidth: model.contentWidth
        )
    }

    private func time(at x: CGFloat) -> TimeInterval {
        TimelineLayout.time(
            at: x,
            duration: model.timelineDuration,
            contentWidth: model.contentWidth
        )
    }

    private func drawSectionBackgrounds(in rect: NSRect) {
        guard !model.sections.isEmpty else { return }

        for (index, section) in model.sections.enumerated() {
            let startX = xPosition(for: section.timelineStartSeconds)
            let endX = xPosition(for: section.timelineEndSeconds)
            guard endX >= rect.minX, startX <= rect.maxX else { continue }

            let palette = ArrangementSectionPalette.colors(for: index)
            let isCued = model.cuedSectionID == section.id
            let opacity = isCued && model.cueFlashPhase
                ? ArrangementSectionPalette.backgroundCueFillOpacity
                : ArrangementSectionPalette.backgroundFillOpacity

            NSColor(palette.background).withAlphaComponent(opacity).setFill()
            NSRect(
                x: startX,
                y: 0,
                width: max(0, endX - startX),
                height: bounds.height
            ).intersection(rect).fill()

            if isCued {
                NSColor(AppColors.accent).withAlphaComponent(model.cueFlashPhase ? 1 : 0.35).setStroke()
                let path = NSBezierPath(
                    rect: NSRect(x: startX, y: 0, width: max(0, endX - startX), height: bounds.height)
                )
                path.lineWidth = 2
                path.stroke()
            }

            NSColor(AppColors.separator).setFill()
            NSRect(x: startX, y: rect.minY, width: 0.5, height: rect.height).intersection(rect).fill()
        }
    }

    private func drawMeasureGrid(in rect: NSRect) {
        guard !model.tempoChanges.isEmpty else { return }

        let pad = time(at: max(0, rect.minX - 40))...time(at: min(model.contentWidth, rect.maxX + 40))
        let boundaries = MeasureTiming.visibleMeasureBoundaries(
            duration: model.timelineDuration,
            tempoChanges: model.tempoChanges,
            contentWidth: model.contentWidth,
            timeSignatureChanges: model.timeSignatureChanges,
            minimumPixelSpacing: model.timelineDuration > 30 * 60 ? 24 : 10,
            visibleTimeRange: pad
        )
        let spacing = pixelsPerBeat()
        let showBeats = model.timelineDuration <= LiveSetlistWaveformMetrics.beatGridMaximumDuration
            && spacing >= LiveSetlistWaveformMetrics.minimumBeatTickSpacing
        let showSubdivisions = showBeats
            && spacing / 2 >= LiveSetlistWaveformMetrics.minimumSubdivisionTickSpacing
        let grid = showBeats
            ? MeasureTiming.beatGridTimes(
                duration: model.timelineDuration,
                tempoChanges: model.tempoChanges,
                timeSignatureChanges: model.timeSignatureChanges,
                visibleTimeRange: pad
            )
            : MeasureTiming.BeatGridTimes(beats: [], subdivisions: [])

        let inset = min(Self.gridInset, bounds.height / 2)
        let lineHeight = max(0, bounds.height - inset * 2)

        if showSubdivisions {
            strokeGridLines(grid.subdivisions, in: rect, inset: inset, lineHeight: lineHeight, opacity: LiveSetlistWaveformMetrics.subdivisionTickOpacity)
        }
        if showBeats {
            strokeGridLines(grid.beats, in: rect, inset: inset, lineHeight: lineHeight, opacity: LiveSetlistWaveformMetrics.beatTickOpacity)
        }
        strokeGridLines(boundaries, in: rect, inset: inset, lineHeight: lineHeight, opacity: LiveSetlistWaveformMetrics.downbeatTickOpacity)
    }

    private func pixelsPerBeat() -> CGFloat {
        let bpm = MeasureTiming.bpmForMeasure(1, tempoChanges: model.tempoChanges)
        let signature = MeasureTiming.numeratorDenominatorForMeasure(1, changes: model.timeSignatureChanges)
        let beatsInMeasure = MeasureTiming.beatsPerMeasure(
            numerator: signature.numerator,
            denominator: signature.denominator
        )
        guard beatsInMeasure > 0, model.timelineDuration > 0, model.contentWidth > 0 else { return 0 }
        let beatDuration = MeasureTiming.measureDuration(
            bpm: bpm,
            numerator: signature.numerator,
            denominator: signature.denominator
        ) / beatsInMeasure
        return CGFloat(beatDuration) * model.contentWidth / CGFloat(model.timelineDuration)
    }

    private func strokeGridLines(
        _ times: [TimeInterval],
        in rect: NSRect,
        inset: CGFloat,
        lineHeight: CGFloat,
        opacity: CGFloat
    ) {
        NSColor.white.withAlphaComponent(opacity).setFill()
        for time in times {
            let x = xPosition(for: time)
            guard x >= rect.minX - 1, x <= rect.maxX + 1 else { continue }
            NSRect(
                x: (x - 0.5).rounded(),
                y: inset,
                width: 1,
                height: lineHeight
            ).intersection(rect).fill()
        }
    }

    private func drawWaveformBars(in rect: NSRect) {
        let midY = bounds.midY
        guard !model.mins.isEmpty, !model.maxes.isEmpty else {
            guard model.isLoading else { return }
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSRect(x: rect.minX, y: midY - 1, width: rect.width, height: 2).fill()
            return
        }

        let scale = max(window?.backingScaleFactor ?? layer?.contentsScale ?? 2, 1)
        let half = bounds.height * WaveformColumnGeometry.amplitudeFraction
        guard half > 0, let prepared = WaveformColumnGeometry.prepare(
            mins: model.mins,
            maxes: model.maxes,
            contentWidth: model.contentWidth,
            rect: rect,
            scale: scale,
            half: half
        ) else { return }

        let path = NSBezierPath(cgPath: WaveformColumnGeometry.envelopePath(
            columns: prepared.columns,
            originX: prepared.originX,
            columnWidth: prepared.columnWidth,
            centerY: midY,
            half: half
        ))

        let playheadX: CGFloat? = {
            guard model.showsPlayheadSplit, let playheadTime = model.playheadTime else { return nil }
            return xPosition(for: min(playheadTime, model.timelineDuration))
        }()

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        if let playheadX {
            // Draw each side once so the played alpha replaces the unplayed
            // alpha instead of compositing on top of it.
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: NSRect(
                x: playheadX,
                y: 0,
                width: max(0, bounds.width - playheadX),
                height: bounds.height
            )).addClip()
            NSColor.white.withAlphaComponent(model.unplayedOpacity).setFill()
            path.fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: max(0, playheadX), height: bounds.height)).addClip()
            NSColor.white.withAlphaComponent(model.playedOpacity).setFill()
            path.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            NSColor.white.setFill()
            path.fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
#endif
