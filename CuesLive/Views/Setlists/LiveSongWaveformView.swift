import SwiftUI
#if os(macOS)
import AppKit
#endif

enum ArrangementSectionPalette {
    /// Saturated section fills — clear section identity without overpowering the waveform.
    private static let pairs: [(background: Color, accent: Color)] = [
        (Color(red: 0.10, green: 0.18, blue: 0.34), Color(red: 0.40, green: 0.68, blue: 1.00)),
        (Color(red: 0.28, green: 0.20, blue: 0.06), Color(red: 0.95, green: 0.78, blue: 0.28)),
        (Color(red: 0.30, green: 0.12, blue: 0.06), Color(red: 1.00, green: 0.55, blue: 0.28)),
        (Color(red: 0.30, green: 0.08, blue: 0.16), Color(red: 1.00, green: 0.42, blue: 0.62)),
        (Color(red: 0.04, green: 0.22, blue: 0.22), Color(red: 0.22, green: 0.88, blue: 0.78)),
        (Color(red: 0.16, green: 0.08, blue: 0.32), Color(red: 0.72, green: 0.48, blue: 1.00)),
    ]

    static let backgroundFillOpacity: Double = 0.30
    static let backgroundCueFillOpacity: Double = 0.48

    static func colors(for index: Int) -> (background: Color, accent: Color) {
        pairs[index % pairs.count]
    }
}

enum LiveSetlistWaveformMetrics {
    static let appStorageKey = "liveSetlistWaveformHeight"
    static let defaultWaveformHeight: CGFloat = 96
    static let defaultWaveformHeightStorageValue = Double(defaultWaveformHeight)
    static let minimumWaveformHeight: CGFloat = 56
    static let maximumWaveformHeight: CGFloat = 200
    static let laneVerticalPadding: CGFloat = 0

    static let horizontalZoomAppStorageKey = "liveSetlistWaveformHorizontalZoom"
    static let defaultHorizontalZoom: CGFloat = 1
    static let defaultHorizontalZoomStorageValue = Double(defaultHorizontalZoom)
    static let minimumHorizontalZoom: CGFloat = 1
    static let maximumHorizontalZoom: CGFloat = 3

    /// Layout-space scroll target for Ableton-style playhead follow.
    static let followPlayheadScrollID = "live-follow-playhead"
    /// Named coordinate space for the live waveform horizontal ScrollView.
    static let scrollCoordinateSpaceName = "live-waveform-scroll"
    /// Re-enable follow when the playhead is this close to the viewport center.
    static let followRelatchDistance: CGFloat = 64

    static func clampedWaveformHeight(_ height: CGFloat) -> CGFloat {
        min(maximumWaveformHeight, max(minimumWaveformHeight, height))
    }

    static func waveformHeight(fromStorage value: Double) -> CGFloat {
        clampedWaveformHeight(CGFloat(value))
    }

    static func storageValue(forHeight waveformHeight: CGFloat) -> Double {
        Double(clampedWaveformHeight(waveformHeight))
    }

    static func laneHeight(for waveformHeight: CGFloat) -> CGFloat {
        clampedWaveformHeight(waveformHeight) + laneVerticalPadding
    }

    static func clampedHorizontalZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumHorizontalZoom, max(minimumHorizontalZoom, zoom))
    }

    static func horizontalZoom(fromStorage value: Double) -> CGFloat {
        clampedHorizontalZoom(CGFloat(value))
    }

    static func storageValue(forZoom horizontalZoom: CGFloat) -> Double {
        Double(clampedHorizontalZoom(horizontalZoom))
    }
}

private struct LiveSetlistWaveformHeightKey: EnvironmentKey {
    static let defaultValue = LiveSetlistWaveformMetrics.defaultWaveformHeight
}

extension EnvironmentValues {
    var liveSetlistWaveformHeight: CGFloat {
        get { self[LiveSetlistWaveformHeightKey.self] }
        set { self[LiveSetlistWaveformHeightKey.self] = newValue }
    }
}

struct LiveSetlistWaveformResizablePanel<Content: View>: View {
    #if os(macOS)
    @AppStorage(LiveSetlistWaveformMetrics.appStorageKey)
    private var storedWaveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeightStorageValue

    @State private var waveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeight
    #endif

    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            content()
                .environment(\.liveSetlistWaveformHeight, waveformHeight)

            LiveSetlistWaveformResizeHandle(
                height: $waveformHeight,
                onResizeEnded: persistWaveformHeight
            )
        }
        .animation(.none, value: waveformHeight)
        .onAppear {
            waveformHeight = LiveSetlistWaveformMetrics.waveformHeight(fromStorage: storedWaveformHeight)
        }
        #else
        content()
            .environment(\.liveSetlistWaveformHeight, LiveSetlistWaveformMetrics.defaultWaveformHeight)
        #endif
    }

    #if os(macOS)
    private func persistWaveformHeight() {
        storedWaveformHeight = LiveSetlistWaveformMetrics.storageValue(forHeight: waveformHeight)
    }
    #endif
}

#if os(macOS)
private struct LiveSetlistWaveformResizeHandle: View {
    @Binding var height: CGFloat
    let onResizeEnded: () -> Void

    @State private var dragStartHeight: CGFloat?

    private static let hitAreaHeight: CGFloat = 24
    private static let adjustmentStep: CGFloat = 8

    var body: some View {
        Capsule()
            .fill(AppColors.textSecondary.opacity(0.55))
            .frame(width: 52, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.hitAreaHeight)
            .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartHeight == nil {
                        dragStartHeight = height
                    }
                    let proposed = (dragStartHeight ?? height) + value.translation.height
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        height = LiveSetlistWaveformMetrics.clampedWaveformHeight(proposed)
                    }
                }
                .onEnded { _ in
                    dragStartHeight = nil
                    onResizeEnded()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waveform height")
        .accessibilityValue("\(Int(LiveSetlistWaveformMetrics.clampedWaveformHeight(height))) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                height = LiveSetlistWaveformMetrics.clampedWaveformHeight(height + Self.adjustmentStep)
            case .decrement:
                height = LiveSetlistWaveformMetrics.clampedWaveformHeight(height - Self.adjustmentStep)
            @unknown default:
                break
            }
            onResizeEnded()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.resizeUpDown.push()
            case .ended:
                NSCursor.pop()
            }
        }
    }
}
#endif

struct LiveSongWaveformView: View {
    let contentWidth: CGFloat
    let trackSources: [(url: URL, duration: TimeInterval)]
    let fileDuration: TimeInterval
    let timelineDuration: TimeInterval
    let sections: [ArrangementDisplaySection]
    let peakSections: [ArrangementDisplaySection]
    let loopSlotIDs: Set<UUID>
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    /// When false, measure ticks are omitted (song has no set/imported tempo).
    var showsMeasureGrid = true
    /// When set, peaks come from the session payload (remote) instead of local audio files.
    var precomputedSourcePeaks: [Float]? = nil
    var showsPlayhead = true
    var isInteractive = true
    /// Visible width of the parent setlist ScrollView (gates long-lane tiled drawing).
    var viewportWidth: CGFloat = 0
    /// When true, skip the full-lane playhead layout target (user is panning).
    var isUserScrolling = false
    /// When true, mount a layout-space follow target for `ScrollViewReader`.
    var needsFollowScrollTarget = false
    /// Observed playhead while stopped/paused so seeks and section taps move the marker.
    /// Omit while playing — live time comes from `playheadTimeProvider` + TimelineView.
    var idlePlayheadTime: TimeInterval? = nil
    var playheadTimeProvider: (() -> TimeInterval)?
    var isPlayingProvider: (() -> Bool)?
    let onSeek: (TimeInterval) -> Void
    let onCueSection: (ArrangementDisplaySection) -> Void

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    @State private var sourcePeaks: [Float] = []
    @State private var cachedDisplayPeaks: [Float] = []

    private static let unplayedWaveformOpacity: Double = 0.32
    /// Above this lane width, use tiled AppKit drawing (macOS) / viewport tiles (iOS).
    private static let tiledLaneMinContentWidth: CGFloat = 1_600
    /// Beat grids are too dense for long songs.
    private static let beatGridMaxDuration: TimeInterval = 10 * 60

    private var safeTimelineDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    private var usesTiledLane: Bool {
        contentWidth > Self.tiledLaneMinContentWidth && viewportWidth > 1
    }

    private var usesArrangementLayout: Bool {
        !sections.isEmpty
    }

    private var usesArrangedPeakMapping: Bool {
        !peakSections.isEmpty
    }

    private var showsFullSourceWaveform: Bool {
        !usesArrangementLayout || !usesArrangedPeakMapping
    }

    private var peaksLoadIdentity: String {
        if let precomputedSourcePeaks {
            let head = precomputedSourcePeaks.prefix(4).map { String(format: "%.4f", $0) }.joined(separator: ",")
            return "precomputed:\(precomputedSourcePeaks.count):\(head)"
        }
        return trackSources
            .map { "\($0.url.path)|\($0.duration)" }
            .joined(separator: ";")
    }

    private var hasPeakSource: Bool {
        if let precomputedSourcePeaks {
            return !precomputedSourcePeaks.isEmpty
        }
        return !trackSources.isEmpty
    }

    private var isLoadingWaveform: Bool {
        hasPeakSource && cachedDisplayPeaks.isEmpty
    }

    var body: some View {
        // Scroll extent stays cheap (`Color.clear`). Long macOS lanes paint via
        // CATiledLayer so SwiftUI never re-layouts a multi‑10k‑pt draw tree while panning.
        Color.clear
            .frame(width: contentWidth, height: waveformHeight)
            .background {
                #if os(macOS)
                if usesTiledLane {
                    scrollBackingLayer
                } else {
                    Color.liveVoiceMemosBackground
                }
                #else
                Color.liveVoiceMemosBackground
                #endif
            }
            .overlay(alignment: .topLeading) {
                #if os(macOS)
                if !usesTiledLane {
                    fullLaneDrawLayer
                }
                #else
                if usesTiledLane {
                    iosTiledDrawLayer
                } else {
                    fullLaneDrawLayer
                }
                #endif
            }
            .overlay(alignment: .topLeading) {
                if showsPlayhead {
                    playheadOverlay(contentWidth: contentWidth)
                }
            }
            .overlay(alignment: .topLeading) {
                // Context-menu section targets are fine on short lanes; long lanes
                // rely on WaveformSeekGestureModifier for cue taps.
                if isInteractive, !usesTiledLane {
                    sectionTapTargets(contentWidth: contentWidth)
                }
            }
            .modifier(LiveSongWaveformClipModifier(usesTiledLane: usesTiledLane))
            .overlay {
                if !usesTiledLane {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            }
            .modifier(WaveformSeekGestureModifier(
                isEnabled: isInteractive,
                contentWidth: contentWidth,
                duration: safeTimelineDuration,
                sections: sections.map {
                    WaveformSeekGestureModifier.SectionHitTarget(
                        id: $0.id,
                        start: $0.timelineStartSeconds,
                        end: $0.timelineEndSeconds
                    )
                },
                onSectionTap: { sectionID in
                    guard let section = sections.first(where: { $0.id == sectionID }) else { return }
                    onCueSection(section)
                },
                onSeek: onSeek
            ))
            .onAppear {
                refreshDisplayPeaks(contentWidth: contentWidth)
            }
            .onChange(of: contentWidth) { _, newWidth in
                refreshDisplayPeaks(contentWidth: newWidth)
            }
            .onChange(of: sourcePeaks.count) { _, _ in
                refreshDisplayPeaks(contentWidth: contentWidth)
            }
            .onChange(of: sections.map(\.id)) { _, _ in
                refreshDisplayPeaks(contentWidth: contentWidth)
            }
            .onChange(of: peakSections.map(\.id)) { _, _ in
                refreshDisplayPeaks(contentWidth: contentWidth)
            }
            .task(id: peaksLoadIdentity) {
                if let precomputedSourcePeaks {
                    sourcePeaks = precomputedSourcePeaks
                    refreshDisplayPeaks(contentWidth: contentWidth)
                    return
                }
                guard !trackSources.isEmpty else {
                    sourcePeaks = []
                    cachedDisplayPeaks = []
                    return
                }
                if let cached = WaveformCache.shared.cachedSummedPeaks(for: trackSources) {
                    sourcePeaks = cached
                } else {
                    sourcePeaks = await WaveformCache.shared.summedPeaks(for: trackSources)
                }
                refreshDisplayPeaks(contentWidth: contentWidth)
            }
    }

    #if os(macOS)
    @ViewBuilder
    private var scrollBackingLayer: some View {
        if resolvedIsPlaying, showsPlayhead {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { _ in
                scrollBacking(
                    playheadTime: resolvedPlayheadTime(live: true),
                    showsPlayheadSplit: true
                )
            }
        } else {
            scrollBacking(
                playheadTime: showsPlayhead ? resolvedPlayheadTime(live: false) : nil,
                showsPlayheadSplit: showsPlayhead
            )
        }
    }

    private func scrollBacking(
        playheadTime: TimeInterval?,
        showsPlayheadSplit: Bool
    ) -> LiveSongWaveformScrollBacking {
        LiveSongWaveformScrollBacking(
            contentWidth: contentWidth,
            timelineDuration: safeTimelineDuration,
            peaks: cachedDisplayPeaks,
            sections: sections,
            loopSlotIDs: loopSlotIDs,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            showsMeasureGrid: showsMeasureGrid,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            playheadTime: playheadTime,
            showsPlayheadSplit: showsPlayheadSplit,
            isLoading: isLoadingWaveform
        )
    }
    #endif

    /// Short-lane SwiftUI drawing (full content — lanes stay under the tile threshold).
    @ViewBuilder
    private var fullLaneDrawLayer: some View {
        let tile = 0...contentWidth
        ZStack(alignment: .leading) {
            sectionColorBackgrounds(contentWidth: contentWidth, tile: tile)
            waveformBars(tile: tile)
            if showsMeasureGrid {
                measureGrid(contentWidth: contentWidth, tile: tile)
            }
            sectionMarkers(contentWidth: contentWidth, tile: tile)
        }
        .frame(width: contentWidth, height: waveformHeight, alignment: .leading)
        .allowsHitTesting(false)
    }

    #if !os(macOS)
    /// iOS long-lane fallback: draw only the visible viewport tile.
    @ViewBuilder
    private var iosTiledDrawLayer: some View {
        GeometryReader { proxy in
            let tile = iosVisibleTileRange(laneFrameInScrollSpace: proxy.frame(
                in: .named(LiveSetlistWaveformMetrics.scrollCoordinateSpaceName)
            ))
            let tileWidth = tile.upperBound - tile.lowerBound

            ZStack(alignment: .leading) {
                sectionColorBackgrounds(contentWidth: contentWidth, tile: tile)
                waveformBars(tile: tile)
                    .frame(width: tileWidth, height: waveformHeight)
                    .offset(x: tile.lowerBound)
                if showsMeasureGrid {
                    measureGrid(contentWidth: contentWidth, tile: tile)
                }
                sectionMarkers(contentWidth: contentWidth, tile: tile)
            }
            .frame(width: contentWidth, height: waveformHeight, alignment: .leading)
        }
        .allowsHitTesting(false)
    }

    private func iosVisibleTileRange(laneFrameInScrollSpace frame: CGRect) -> ClosedRange<CGFloat> {
        let overscan: CGFloat = 240
        let quantum: CGFloat = 80
        let visibleStart = -frame.minX
        let rawStart = visibleStart - overscan
        let rawEnd = visibleStart + max(viewportWidth, 1) + overscan
        let start = max(0, floor(rawStart / quantum) * quantum)
        let end = min(contentWidth, max(start + 1, ceil(rawEnd / quantum) * quantum))
        return start...end
    }
    #endif

    @ViewBuilder
    private func sectionColorBackgrounds(contentWidth: CGFloat, tile: ClosedRange<CGFloat>) -> some View {
        let tileWidth = max(1, tile.upperBound - tile.lowerBound)
        if usesArrangementLayout {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.liveVoiceMemosBackground)
                    .frame(width: tileWidth, height: waveformHeight)
                    .offset(x: tile.lowerBound)

                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    let startX = TimelineLayout.xPosition(
                        for: section.timelineStartSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let endX = TimelineLayout.xPosition(
                        for: section.timelineEndSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    if endX >= tile.lowerBound, startX <= tile.upperBound {
                        let segmentWidth = max(0, endX - startX)
                        let palette = ArrangementSectionPalette.colors(for: index)
                        let isCued = cuedSectionID == section.id

                        Rectangle()
                            .fill(
                                palette.background.opacity(
                                    isCued && cueFlashPhase
                                        ? ArrangementSectionPalette.backgroundCueFillOpacity
                                        : ArrangementSectionPalette.backgroundFillOpacity
                                )
                            )
                            .frame(width: segmentWidth, height: waveformHeight)
                            .overlay {
                                if isCued {
                                    Rectangle()
                                        .stroke(AppColors.accent.opacity(cueFlashPhase ? 1 : 0.35), lineWidth: 2)
                                }
                            }
                            .offset(x: startX)

                        Rectangle()
                            .fill(AppColors.separator)
                            .frame(width: 0.5, height: waveformHeight)
                            .offset(x: startX)
                    }
                }
            }
        } else {
            Rectangle()
                .fill(Color.liveVoiceMemosBackground)
                .frame(width: tileWidth, height: waveformHeight)
                .offset(x: tile.lowerBound)
        }
    }

    @ViewBuilder
    private func waveformBars(tile: ClosedRange<CGFloat>) -> some View {
        let timelineStart = TimelineLayout.time(
            at: tile.lowerBound,
            duration: safeTimelineDuration,
            contentWidth: contentWidth
        )
        let timelineEnd = TimelineLayout.time(
            at: tile.upperBound,
            duration: safeTimelineDuration,
            contentWidth: contentWidth
        )
        let tileBars: [Float] = {
            guard !cachedDisplayPeaks.isEmpty else { return [] }
            if tile.lowerBound > 0 || tile.upperBound < contentWidth {
                return WaveformPeakResampler.peaksSlice(
                    from: cachedDisplayPeaks,
                    timelineStart: timelineStart,
                    timelineEnd: timelineEnd,
                    timelineDuration: safeTimelineDuration
                )
            }
            return cachedDisplayPeaks
        }()

        let playheadFraction: CGFloat? = {
            guard showsPlayhead else { return nil }
            let time = resolvedPlayheadTime(live: resolvedIsPlaying)
            let span = max(0.0001, timelineEnd - timelineStart)
            return CGFloat((time - timelineStart) / span)
        }()

        Group {
            if resolvedIsPlaying, showsPlayhead {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    let time = resolvedPlayheadTime(live: true)
                    let span = max(0.0001, timelineEnd - timelineStart)
                    let fraction = CGFloat((time - timelineStart) / span)
                    WaveformBarsCanvas(
                        bars: tileBars,
                        showsEmptyBaseline: isLoadingWaveform || showsFullSourceWaveform,
                        fillColor: .white,
                        style: .voiceMemosBars,
                        playheadFraction: fraction,
                        playedColor: .white,
                        unplayedColor: .white.opacity(Self.unplayedWaveformOpacity),
                        usesDrawingGroup: false
                    )
                }
            } else {
                WaveformBarsCanvas(
                    bars: tileBars,
                    showsEmptyBaseline: isLoadingWaveform || showsFullSourceWaveform,
                    fillColor: .white,
                    style: .voiceMemosBars,
                    playheadFraction: playheadFraction,
                    playedColor: .white,
                    unplayedColor: .white.opacity(Self.unplayedWaveformOpacity),
                    usesDrawingGroup: contentWidth <= Self.tiledLaneMinContentWidth
                )
            }
        }
    }

    @ViewBuilder
    private func sectionMarkers(contentWidth: CGFloat, tile: ClosedRange<CGFloat>) -> some View {
        if usesArrangementLayout {
            ZStack(alignment: .leading) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    let startX = TimelineLayout.xPosition(
                        for: section.timelineStartSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let endX = TimelineLayout.xPosition(
                        for: section.timelineEndSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    if endX >= tile.lowerBound, startX <= tile.upperBound {
                        let segmentWidth = max(0, endX - startX)
                        let palette = ArrangementSectionPalette.colors(for: index)
                        let isLoopSection = loopSlotIDs.contains(section.id)

                        HStack(spacing: 3) {
                            if isLoopSection {
                                Image(systemName: "repeat")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(palette.accent)
                            }
                            Text(section.name.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.accent)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.surfaceElevated.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        .padding(.leading, 4)
                        .padding(.top, 4)
                        .frame(width: segmentWidth, height: waveformHeight, alignment: .topLeading)
                        .offset(x: startX)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func measureGrid(contentWidth: CGFloat, tile: ClosedRange<CGFloat>) -> some View {
        let tileWidth = max(1, tile.upperBound - tile.lowerBound)
        let tileOrigin = tile.lowerBound

        return Canvas { context, size in
            guard size.width > 0, size.height > 0, !tempoChanges.isEmpty else { return }

            let showBeats = safeTimelineDuration <= Self.beatGridMaxDuration
                && shouldShowBeatLines(contentWidth: contentWidth)

            let measureBoundaries = MeasureTiming.visibleMeasureBoundaries(
                duration: safeTimelineDuration,
                tempoChanges: tempoChanges,
                contentWidth: contentWidth,
                timeSignatureChanges: timeSignatureChanges,
                minimumPixelSpacing: safeTimelineDuration > 30 * 60 ? 24 : 10,
                visibleTimeRange: TimelineLayout.time(
                    at: tile.lowerBound,
                    duration: safeTimelineDuration,
                    contentWidth: contentWidth
                )...TimelineLayout.time(
                    at: tile.upperBound,
                    duration: safeTimelineDuration,
                    contentWidth: contentWidth
                )
            )

            let beatLineColor = Color.white.opacity(0.22)
            let measureLineColor = Color.white.opacity(0.65)

            if showBeats {
                for time in beatBoundaries() {
                    strokeGridLine(
                        at: time,
                        contentWidth: contentWidth,
                        tileOrigin: tileOrigin,
                        size: size,
                        color: beatLineColor,
                        in: context
                    )
                }
            }

            for time in measureBoundaries {
                strokeGridLine(
                    at: time,
                    contentWidth: contentWidth,
                    tileOrigin: tileOrigin,
                    size: size,
                    color: measureLineColor,
                    in: context
                )
            }
        }
        .frame(width: tileWidth, height: waveformHeight)
        .offset(x: tileOrigin)
        .allowsHitTesting(false)
    }

    private func shouldShowBeatLines(contentWidth: CGFloat) -> Bool {
        let bpm = MeasureTiming.bpmForMeasure(1, tempoChanges: tempoChanges)
        let signature = MeasureTiming.numeratorDenominatorForMeasure(1, changes: timeSignatureChanges)
        let beatsInMeasure = MeasureTiming.beatsPerMeasure(
            numerator: signature.numerator,
            denominator: signature.denominator
        )
        guard beatsInMeasure > 0 else { return false }

        let beatDuration = MeasureTiming.measureDuration(
            bpm: bpm,
            numerator: signature.numerator,
            denominator: signature.denominator
        ) / beatsInMeasure
        let pixelsPerBeat = CGFloat(beatDuration) * contentWidth / CGFloat(safeTimelineDuration)
        return pixelsPerBeat >= 8
    }

    private func beatBoundaries() -> [TimeInterval] {
        var times: [TimeInterval] = []
        var measure = 1

        while measure < 1_000_000 {
            let measureStart = MeasureTiming.timeAtStartOfMeasure(
                measure,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges
            )
            guard measureStart < safeTimelineDuration - 0.0001 else { break }

            let bpm = MeasureTiming.bpmForMeasure(measure, tempoChanges: tempoChanges)
            let signature = MeasureTiming.numeratorDenominatorForMeasure(
                measure,
                changes: timeSignatureChanges
            )
            let beatsInMeasure = MeasureTiming.beatsPerMeasure(
                numerator: signature.numerator,
                denominator: signature.denominator
            )
            let measureDuration = MeasureTiming.measureDuration(
                bpm: bpm,
                numerator: signature.numerator,
                denominator: signature.denominator
            )
            guard beatsInMeasure > 0, measureDuration > 0 else {
                measure += 1
                continue
            }

            let beatDuration = measureDuration / beatsInMeasure
            let beatCount = max(0, Int(beatsInMeasure.rounded(.down)))
            for beatIndex in 1..<beatCount {
                let time = measureStart + TimeInterval(beatIndex) * beatDuration
                guard time < safeTimelineDuration - 0.0001 else { break }
                times.append(time)
            }

            measure += 1
        }

        return times
    }

    private static let gridLineVerticalInset: CGFloat = 8
    private static let gridLineWidth: CGFloat = 1

    private func strokeGridLine(
        at time: TimeInterval,
        contentWidth: CGFloat,
        tileOrigin: CGFloat,
        size: CGSize,
        color: Color,
        in context: GraphicsContext
    ) {
        let absoluteX = TimelineLayout.xPosition(
            for: time,
            duration: safeTimelineDuration,
            contentWidth: contentWidth
        )
        let x = absoluteX - tileOrigin
        guard x >= -1, x <= size.width + 1 else { return }

        let inset = min(Self.gridLineVerticalInset, size.height / 2)
        let height = max(0, size.height - inset * 2)
        let rect = CGRect(
            x: (x - Self.gridLineWidth / 2).rounded(),
            y: inset,
            width: Self.gridLineWidth,
            height: height
        )
        var context = context
        context.fill(Path(rect), with: .color(color))
    }

    @ViewBuilder
    private func sectionTapTargets(contentWidth: CGFloat) -> some View {
        if usesArrangementLayout {
            ZStack(alignment: .leading) {
                ForEach(sections) { section in
                    let startX = TimelineLayout.xPosition(
                        for: section.timelineStartSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let endX = TimelineLayout.xPosition(
                        for: section.timelineEndSeconds,
                        duration: safeTimelineDuration,
                        contentWidth: contentWidth
                    )
                    let segmentWidth = max(0, endX - startX)

                    Color.clear
                        .frame(width: segmentWidth, height: waveformHeight)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Cue Section") {
                                onCueSection(section)
                            }
                        }
                        .offset(x: startX)
                }
            }
        }
    }

    @ViewBuilder
    private func playheadOverlay(contentWidth: CGFloat) -> some View {
        if resolvedIsPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                playheadMarker(
                    at: resolvedPlayheadTime(live: true),
                    contentWidth: contentWidth
                )
            }
        } else {
            playheadMarker(
                at: resolvedPlayheadTime(live: false),
                contentWidth: contentWidth
            )
        }
    }

    @ViewBuilder
    private func playheadMarker(at time: TimeInterval, contentWidth: CGFloat) -> some View {
        let x = TimelineLayout.xPosition(
            for: min(time, safeTimelineDuration),
            duration: safeTimelineDuration,
            contentWidth: contentWidth
        )
        let clampedX = max(0, min(x, contentWidth))
        // Avoid a full-lane playhead layout tree while the user is panning a long lane.
        let usesCompactPlayhead = usesTiledLane && (isUserScrolling || !needsFollowScrollTarget)

        ZStack(alignment: .leading) {
            if !usesCompactPlayhead {
                // Layout-space target so ScrollViewReader can center on the playhead.
                HStack(spacing: 0) {
                    Color.clear.frame(width: clampedX)
                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(LiveSetlistWaveformMetrics.followPlayheadScrollID)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: LiveSetlistPlayheadViewportXKey.self,
                                    value: geometry.frame(
                                        in: .named(LiveSetlistWaveformMetrics.scrollCoordinateSpaceName)
                                    ).midX
                                )
                            }
                        }
                    Spacer(minLength: 0)
                }
                .frame(width: contentWidth, height: 1, alignment: .leading)
            }

            Rectangle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 2, height: waveformHeight)
                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 0)
                .offset(x: usesCompactPlayhead ? 0 : clampedX - 1)
        }
        .frame(
            width: usesCompactPlayhead ? 2 : contentWidth,
            height: waveformHeight,
            alignment: .leading
        )
        .offset(x: usesCompactPlayhead ? clampedX - 1 : 0)
        .background(alignment: .topLeading) {
            if usesCompactPlayhead {
                Color.clear
                    .frame(width: 1, height: 1)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: LiveSetlistPlayheadViewportXKey.self,
                                value: geometry.frame(
                                    in: .named(LiveSetlistWaveformMetrics.scrollCoordinateSpaceName)
                                ).midX
                            )
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private func resolvedPlayheadTime(live: Bool) -> TimeInterval {
        if live {
            if let playheadTimeProvider {
                return playheadTimeProvider()
            }
            return AudioEngineManager.shared.livePlayheadTime()
        }
        if let idlePlayheadTime {
            return idlePlayheadTime
        }
        if let playheadTimeProvider {
            return playheadTimeProvider()
        }
        // Avoid `@Bindable` on the shared engine — observation would rebuild this
        // lane on every transport/meter tick and hitch scrolling.
        return AudioEngineManager.shared.currentTime
    }

    private var resolvedIsPlaying: Bool {
        if let isPlayingProvider {
            return isPlayingProvider()
        }
        return AudioEngineManager.shared.isPlaying
    }

    private func refreshDisplayPeaks(contentWidth: CGFloat) {
        guard contentWidth > 0 else { return }

        if showsFullSourceWaveform {
            cachedDisplayPeaks = WaveformPeakResampler.displayPeaks(
                from: sourcePeaks,
                contentWidth: contentWidth,
                minimumBarSlotWidth: WaveformPeakResampler.voiceMemosBarSlotWidth,
                maximumBars: nil
            )
        } else {
            cachedDisplayPeaks = WaveformPeakResampler.arrangedDisplayPeaks(
                from: sourcePeaks,
                fileDuration: fileDuration,
                sections: peakSections,
                timelineDuration: safeTimelineDuration,
                contentWidth: contentWidth,
                minimumBarSlotWidth: WaveformPeakResampler.voiceMemosBarSlotWidth,
                maximumBars: nil
            )
        }
    }
}

/// Avoid clipping a multi‑tens‑of‑thousands‑pt rounded rect for long songs.
private struct LiveSongWaveformClipModifier: ViewModifier {
    let usesTiledLane: Bool

    func body(content: Content) -> some View {
        if usesTiledLane {
            content
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }
}

struct SetlistWaveformHeaderMarker: View {
    let title: String

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    private let markerWidth: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColors.backgroundPrimary)
            .overlay {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    // Lay out along the vertical axis before rotating into the marker.
                    .frame(width: max(0, waveformHeight - AppSpacing.md), height: markerWidth)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: markerWidth, height: waveformHeight)
            .clipped()
    }
}

struct LiveSetlistWaveformScrollView: View {
    let timelineItems: [LiveSetlistTimelineItem]
    let currentPlaybackIndex: Int
    let waveformSnapshotForSongID: (UUID) -> LiveSongWaveformSnapshot?
    let ensureWaveformSnapshotForSongID: (UUID) -> Void
    let playheadTimeProvider: () -> TimeInterval
    let isPlayingProvider: () -> Bool
    /// Observed while stopped/paused so the playhead moves on seek/section tap.
    var idlePlayheadTime: TimeInterval? = nil
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    let onSeek: (TimeInterval) -> Void
    let onCueSection: (ArrangementDisplaySection) -> Void
    var onOverlapBadgeTapped: ((Int) -> Void)?
    /// When set, tapping a non-current song lane selects that song (remote client).
    var onSelectSong: ((Int) -> Void)?

    @AppStorage(LiveSetlistWaveformMetrics.horizontalZoomAppStorageKey)
    private var storedHorizontalZoom = LiveSetlistWaveformMetrics.defaultHorizontalZoomStorageValue

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    @State private var isFollowing = true
    @State private var isUserScrolling = false
    @State private var playheadViewportX: CGFloat?
    @State private var viewportWidth: CGFloat = 1
    @State private var horizontalZoom = LiveSetlistWaveformMetrics.defaultHorizontalZoom
    @State private var pinchStartZoom: CGFloat?

    private let laneSpacing: CGFloat = 24
    private static let zoomAdjustmentStep: CGFloat = 0.25

    private var laneHeight: CGFloat {
        LiveSetlistWaveformMetrics.laneHeight(for: waveformHeight)
    }

    private var currentSongScrollID: String {
        "song-\(currentPlaybackIndex)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: laneSpacing) {
                    ForEach(timelineItems) { item in
                        timelineItemView(item)
                    }
                }
                .padding(.leading, AppSpacing.md)
                .padding(.vertical, 2)
                .frame(minWidth: viewportWidth, alignment: .leading)
            }
            .defaultScrollAnchor(.leading)
            // Keep a single scrollTargetBehavior instance so toggling follow does not
            // recreate the ScrollView (which would jump to defaultScrollAnchor).
            .scrollTargetBehavior(LiveSetlistFollowScrollTargetBehavior(isFollowing: isFollowing))
            .coordinateSpace(name: LiveSetlistWaveformMetrics.scrollCoordinateSpaceName)
            .modifier(LiveSetlistFollowUserScrollDetector(
                isFollowing: $isFollowing,
                isUserScrolling: $isUserScrolling
            ))
            .onPreferenceChange(LiveSetlistPlayheadViewportXKey.self) { playheadX in
                // Preference updates during a drag rebuild the scroll hierarchy
                // and amplify hitching on very wide lanes.
                guard !isUserScrolling else { return }
                guard let playheadX else {
                    playheadViewportX = nil
                    return
                }
                // Avoid rebuilding scroll state on sub-pixel preference chatter.
                if let playheadViewportX, abs(playheadViewportX - playheadX) < 1 {
                    return
                }
                playheadViewportX = playheadX
                attemptFollowRelatch()
            }
            .onChange(of: isUserScrolling) { _, scrolling in
                if !scrolling {
                    attemptFollowRelatch()
                }
            }
            .onAppear {
                if isFollowing {
                    scrollToFollowPlayhead(proxy, requirePlaying: false, deferred: true)
                } else {
                    scrollToCurrent(proxy)
                }
            }
            .onChange(of: currentPlaybackIndex) { _, _ in
                if isFollowing {
                    scrollToFollowPlayhead(proxy, requirePlaying: false, deferred: true)
                } else {
                    scrollToCurrent(proxy)
                }
            }
            .onChange(of: isFollowing) { _, following in
                if following {
                    scrollToFollowPlayhead(proxy, requirePlaying: false, deferred: true)
                }
            }
            .background {
                if isFollowing {
                    TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                        LiveSetlistFollowScrollDriver(date: context.date) {
                            guard isPlayingProvider() else { return }
                            scrollToFollowPlayhead(proxy, requirePlaying: true)
                        }
                    }
                }
            }
        }
        .simultaneousGesture(horizontalPinchGesture)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size.width, initial: true) { _, width in
                        viewportWidth = max(width, 1)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: laneHeight)
        .animation(.none, value: waveformHeight)
        .animation(.none, value: horizontalZoom)
        .onAppear {
            horizontalZoom = LiveSetlistWaveformMetrics.horizontalZoom(fromStorage: storedHorizontalZoom)
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setHorizontalZoom(horizontalZoom + Self.zoomAdjustmentStep)
            case .decrement:
                setHorizontalZoom(horizontalZoom - Self.zoomAdjustmentStep)
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func timelineItemView(_ item: LiveSetlistTimelineItem) -> some View {
        switch item {
        case .header(_, let title):
            SetlistWaveformHeaderMarker(title: title)
                .id(item.id)

        case .song(let songID, let playbackIndex, let transitionAfter):
            HStack(alignment: .center, spacing: laneSpacing) {
                songLane(songID: songID, playbackIndex: playbackIndex)
                    .id(item.id)

                if let transitionAfter {
                    transitionBadge(transitionAfter, playbackIndex: playbackIndex)
                }
            }
        }
    }

    private func transitionBadge(_ transition: SetlistTransition, playbackIndex: Int) -> some View {
        SetlistTransitionBadge(
            transition: transition,
            onTap: transition == .overlap
                ? { onOverlapBadgeTapped?(playbackIndex) }
                : nil
        )
        .frame(height: waveformHeight)
    }

    private var horizontalPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStartZoom == nil {
                    pinchStartZoom = horizontalZoom
                }
                guard let pinchStartZoom else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    horizontalZoom = LiveSetlistWaveformMetrics.clampedHorizontalZoom(pinchStartZoom * scale)
                }
            }
            .onEnded { _ in
                pinchStartZoom = nil
                persistHorizontalZoom()
            }
    }

    private func setHorizontalZoom(_ proposed: CGFloat) {
        horizontalZoom = LiveSetlistWaveformMetrics.clampedHorizontalZoom(proposed)
        persistHorizontalZoom()
    }

    private func persistHorizontalZoom() {
        storedHorizontalZoom = LiveSetlistWaveformMetrics.storageValue(forZoom: horizontalZoom)
    }

    private func laneContentWidth(for snapshot: LiveSongWaveformSnapshot) -> CGFloat {
        TimelineLayout.contentWidth(for: snapshot.timelineDuration, zoom: horizontalZoom)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(currentSongScrollID, anchor: .leading)
            }
        }
    }

    private func scrollToFollowPlayhead(
        _ proxy: ScrollViewProxy,
        requirePlaying: Bool,
        deferred: Bool = false
    ) {
        let perform = {
            guard self.isFollowing else { return }
            if requirePlaying, !self.isPlayingProvider() { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(
                    LiveSetlistWaveformMetrics.followPlayheadScrollID,
                    anchor: .center
                )
            }
        }

        if deferred {
            Task { @MainActor in
                await Task.yield()
                perform()
            }
        } else {
            perform()
        }
    }

    private func attemptFollowRelatch() {
        guard !isFollowing, !isUserScrolling, let playheadViewportX else { return }
        let center = viewportWidth / 2
        guard abs(playheadViewportX - center) <= LiveSetlistWaveformMetrics.followRelatchDistance else {
            return
        }
        isFollowing = true
    }

    @ViewBuilder
    private func songLane(songID: UUID, playbackIndex: Int) -> some View {
        let isCurrent = playbackIndex == currentPlaybackIndex

        Group {
            if let snapshot = waveformSnapshotForSongID(songID) {
                waveformLane(snapshot: snapshot, isCurrent: isCurrent)
            } else {
                LiveSetlistWaveformLanePlaceholder(isCurrent: isCurrent)
                    .task(id: songID) {
                        ensureWaveformSnapshotForSongID(songID)
                    }
            }
        }
        .modifier(NonCurrentSongSelectTapModifier(
            isEnabled: !isCurrent && onSelectSong != nil,
            onSelect: { onSelectSong?(playbackIndex) }
        ))
    }

    @ViewBuilder
    private func waveformLane(
        snapshot: LiveSongWaveformSnapshot,
        isCurrent: Bool
    ) -> some View {
        let laneContentWidth = laneContentWidth(for: snapshot)

        LiveSongWaveformView(
            contentWidth: laneContentWidth,
            trackSources: snapshot.trackSources,
            fileDuration: snapshot.fileDuration,
            timelineDuration: snapshot.timelineDuration,
            sections: snapshot.sections,
            peakSections: snapshot.peakSections,
            loopSlotIDs: snapshot.loopSlotIDs,
            tempoChanges: snapshot.tempoChanges,
            timeSignatureChanges: snapshot.timeSignatureChanges,
            cuedSectionID: isCurrent ? cuedSectionID : nil,
            cueFlashPhase: isCurrent ? cueFlashPhase : false,
            showsMeasureGrid: snapshot.showsMeasureGrid,
            precomputedSourcePeaks: snapshot.precomputedSourcePeaks,
            showsPlayhead: isCurrent,
            isInteractive: isCurrent,
            viewportWidth: viewportWidth,
            isUserScrolling: isUserScrolling,
            needsFollowScrollTarget: isCurrent && isFollowing,
            idlePlayheadTime: isCurrent ? idlePlayheadTime : nil,
            playheadTimeProvider: isCurrent ? playheadTimeProvider : nil,
            isPlayingProvider: isCurrent ? isPlayingProvider : nil,
            onSeek: onSeek,
            onCueSection: onCueSection
        )
        .opacity(isCurrent ? 1 : 0.72)
    }
}

private struct LiveSetlistWaveformLanePlaceholder: View {
    let isCurrent: Bool

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColors.backgroundPrimary)
            .frame(width: 180, height: waveformHeight)
            .opacity(isCurrent ? 1 : 0.72)
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
    }
}

private struct NonCurrentSongSelectTapModifier: ViewModifier {
    let isEnabled: Bool
    let onSelect: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onTapGesture(perform: onSelect)
        } else {
            content
        }
    }
}

/// View-aligned snapping while free-scrolling; no-op while following the playhead.
/// Implemented as `ScrollTargetBehavior` (not a conditional `ViewModifier`) so
/// enabling/disabling follow does not change ScrollView identity or reset offset.
struct LiveSetlistFollowScrollTargetBehavior: ScrollTargetBehavior {
    var isFollowing: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard !isFollowing else { return }
        ViewAlignedScrollTargetBehavior().updateTarget(&target, context: context)
    }
}

struct LiveSetlistFollowScrollDriver: View {
    let date: Date
    let action: () -> Void

    var body: some View {
        Color.clear
            .onAppear(perform: action)
            .onChange(of: date) { _, _ in
                action()
            }
    }
}

struct LiveSetlistFollowUserScrollDetector: ViewModifier {
    @Binding var isFollowing: Bool
    @Binding var isUserScrolling: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .interacting, .decelerating:
                        isUserScrolling = true
                        isFollowing = false
                    default:
                        isUserScrolling = false
                    }
                }
        } else {
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { _ in
                            isUserScrolling = true
                            isFollowing = false
                        }
                        .onEnded { _ in
                            isUserScrolling = false
                        }
                )
        }
    }
}

private struct LiveSetlistPlayheadViewportXKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Tap seeks; drag is left to the parent horizontal ScrollView for panning.
/// When arrangement sections are provided, a tap inside a section jumps to that
/// section (via `onSectionTap`) instead of the exact tap time — matching Mac.
struct WaveformSeekGestureModifier: ViewModifier {
    struct SectionHitTarget: Identifiable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval
    }

    let isEnabled: Bool
    let contentWidth: CGFloat
    let duration: TimeInterval
    var sections: [SectionHitTarget] = []
    var onSectionTap: ((UUID) -> Void)? = nil
    let onSeek: (TimeInterval) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            let time = TimelineLayout.time(
                                at: event.location.x,
                                duration: duration,
                                contentWidth: contentWidth
                            )
                            if let onSectionTap, let sectionID = sectionID(containing: time) {
                                onSectionTap(sectionID)
                            } else {
                                onSeek(time)
                            }
                        }
                )
        } else {
            content
        }
    }

    private func sectionID(containing time: TimeInterval) -> UUID? {
        guard !sections.isEmpty else { return nil }

        for section in sections {
            if time >= section.start && time < section.end {
                return section.id
            }
        }

        if let last = sections.last, time >= last.start && time <= last.end {
            return last.id
        }

        return nil
    }
}
