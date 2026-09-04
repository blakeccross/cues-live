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
    var peaks: [Float]
    var sections: [ArrangementDisplaySection]
    var loopSlotIDs: Set<UUID>
    var tempoChanges: [TempoChange]
    var timeSignatureChanges: [TimeSignatureChange]
    var showsMeasureGrid: Bool
    var cuedSectionID: UUID?
    var cueFlashPhase: Bool
    var playheadTime: TimeInterval?
    var showsPlayheadSplit: Bool
    var isLoading: Bool

    private static let unplayedOpacity: CGFloat = 0.32

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
            peaks: peaks,
            sections: sections,
            loopSlotIDs: loopSlotIDs,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            showsMeasureGrid: showsMeasureGrid,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            playheadTime: playheadTime,
            showsPlayheadSplit: showsPlayheadSplit,
            unplayedOpacity: Self.unplayedOpacity,
            isLoading: isLoading
        )
    }
}

final class LiveSongWaveformScrollBackingView: NSView {
    struct Model: Equatable {
        var contentWidth: CGFloat = 1
        var timelineDuration: TimeInterval = 1
        var peaks: [Float] = []
        var sections: [ArrangementDisplaySection] = []
        var loopSlotIDs: Set<UUID> = []
        var tempoChanges: [TempoChange] = []
        var timeSignatureChanges: [TimeSignatureChange] = []
        var showsMeasureGrid = true
        var cuedSectionID: UUID?
        var cueFlashPhase = false
        var playheadTime: TimeInterval?
        var showsPlayheadSplit = false
        var unplayedOpacity: CGFloat = 0.32
        var isLoading = false

        func structurallyEquals(_ other: Model) -> Bool {
            contentWidth == other.contentWidth
                && timelineDuration == other.timelineDuration
                && peaks == other.peaks
                && sections == other.sections
                && loopSlotIDs == other.loopSlotIDs
                && tempoChanges == other.tempoChanges
                && timeSignatureChanges == other.timeSignatureChanges
                && showsMeasureGrid == other.showsMeasureGrid
                && cuedSectionID == other.cuedSectionID
                && cueFlashPhase == other.cueFlashPhase
                && showsPlayheadSplit == other.showsPlayheadSplit
                && unplayedOpacity == other.unplayedOpacity
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
        layerContentsRedrawPolicy = .onSetNeedsDisplay
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

    override func setFrameSize(_ newSize: NSSize) {
        let changed = bounds.size != newSize
        super.setFrameSize(newSize)
        if changed {
            needsDisplay = true
        }
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
        drawSectionLabels(in: rect)
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

        NSColor.white.withAlphaComponent(0.65).setFill()
        let inset = min(Self.gridInset, bounds.height / 2)
        let lineHeight = max(0, bounds.height - inset * 2)

        for boundary in boundaries {
            let x = xPosition(for: boundary)
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
        let maxBarHeight = bounds.height * 0.88
        let playheadX: CGFloat? = {
            guard model.showsPlayheadSplit, let playheadTime = model.playheadTime else { return nil }
            return xPosition(for: min(playheadTime, model.timelineDuration))
        }()

        if model.peaks.isEmpty {
            guard model.isLoading else { return }
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSRect(x: rect.minX, y: midY - 1, width: rect.width, height: 2).fill()
            return
        }

        let barCount = model.peaks.count
        let barSlotWidth = model.contentWidth / CGFloat(barCount)
        let barWidth = min(max(1.5, barSlotWidth * 0.55), 4.0)
        let startIndex = max(0, Int(floor(rect.minX / barSlotWidth)) - 1)
        let endIndex = min(barCount - 1, Int(ceil(rect.maxX / barSlotWidth)) + 1)
        guard startIndex <= endIndex else { return }

        for index in startIndex...endIndex {
            let centerX = CGFloat(index) * barSlotWidth + barSlotWidth * 0.5
            let barHeight = max(2, CGFloat(model.peaks[index]) * maxBarHeight)
            let alpha: CGFloat = {
                guard let playheadX else { return 1 }
                return centerX <= playheadX ? 1 : model.unplayedOpacity
            }()
            NSColor.white.withAlphaComponent(alpha).setFill()
            let barRect = NSRect(
                x: centerX - barWidth / 2,
                y: midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    private func drawSectionLabels(in rect: NSRect) {
        guard !model.sections.isEmpty else { return }

        for (index, section) in model.sections.enumerated() {
            let startX = xPosition(for: section.timelineStartSeconds)
            let endX = xPosition(for: section.timelineEndSeconds)
            guard endX >= rect.minX, startX <= rect.maxX else { continue }

            let palette = ArrangementSectionPalette.colors(for: index)
            let title: String
            if model.loopSlotIDs.contains(section.id) {
                title = "↻ \(section.name.uppercased())"
            } else {
                title = section.name.uppercased()
            }
            let text = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor(palette.accent),
            ])
            let textSize = text.size()
            let labelOrigin = NSPoint(x: startX + 4, y: 4)
            let background = NSRect(
                x: labelOrigin.x,
                y: labelOrigin.y,
                width: textSize.width + 10,
                height: textSize.height + 4
            )
            guard background.intersects(rect) else { continue }

            NSColor(AppColors.surfaceElevated).withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
            text.draw(at: NSPoint(x: labelOrigin.x + 5, y: labelOrigin.y + 2))
        }
    }
}
#endif
