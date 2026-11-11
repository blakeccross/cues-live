import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct LiveSongWaveformView: View {
    let contentWidth: CGFloat
    let trackSources: [(url: URL, duration: TimeInterval)]
    let fileDuration: TimeInterval
    let timelineDuration: TimeInterval
    let sections: [SongSection]
    let peakClips: [TrackClip]
    let loopSectionIDs: Set<UUID>
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
    /// Shows a caution icon in every section when the song has missing audio files.
    var showsMissingMediaWarning = false
    /// Observed playhead while stopped/paused so seeks and section taps move the marker.
    /// Omit while playing — live time comes from `playheadTimeProvider` + TimelineView.
    var idlePlayheadTime: TimeInterval? = nil
    var playheadTimeProvider: (() -> TimeInterval)?
    var isPlayingProvider: (() -> Bool)?
    let onSeek: (TimeInterval) -> Void
    let onCueSection: (SongSection) -> Void
    /// Setlist position of this lane. When set, each section can be key- or MIDI-mapped.
    var playbackIndex: Int? = nil

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight
    @Environment(InputMappingController.self) private var mapping

    @State private var sourceSeries = WaveformMinMax.empty
    @State private var cachedDisplaySeries = WaveformMinMax.empty

    /// Above this lane width, use tiled AppKit drawing (macOS) / viewport tiles (iOS).
    private static let tiledLaneMinContentWidth: CGFloat = 1_600
    /// Beat grids are too dense for long songs.
    private static let beatGridMaxDuration = LiveSetlistWaveformMetrics.beatGridMaximumDuration

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
        !peakClips.isEmpty
    }

    private var showsFullSourceWaveform: Bool {
        !usesArrangementLayout || !usesArrangedPeakMapping
    }

    private var peaksLoadIdentity: String {
        if !trackSources.isEmpty {
            return trackSources
                .map { "\($0.url.path)|\($0.duration)" }
                .joined(separator: ";")
        }
        if let precomputedSourcePeaks {
            let head = precomputedSourcePeaks.prefix(4).map { String(format: "%.4f", $0) }.joined(separator: ",")
            return "precomputed:\(precomputedSourcePeaks.count):\(head)"
        }
        return ""
    }

    private var hasPeakSource: Bool {
        if let precomputedSourcePeaks {
            return !precomputedSourcePeaks.isEmpty
        }
        return !trackSources.isEmpty
    }

    private var isLoadingWaveform: Bool {
        hasPeakSource && cachedDisplaySeries.isEmpty
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
                if usesTiledLane {
                    // Labels stay live text. Painting them into the tiled layer
                    // rasterizes them at 1× and they look soft on a Retina display.
                    sectionMarkers(contentWidth: contentWidth, tile: 0...contentWidth)
                        .frame(width: contentWidth, height: waveformHeight, alignment: .leading)
                        .allowsHitTesting(false)
                } else {
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
            .overlay(alignment: .topLeading) {
                if let playbackIndex, mapping.showsLiveHighlights {
                    sectionMappingTargets(playbackIndex: playbackIndex, contentWidth: contentWidth)
                }
            }
            .modifier(WaveformSeekGestureModifier(
                isEnabled: isInteractive && !mapping.showsLiveHighlights,
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
                refreshDisplayPeaks()
            }
            .onChange(of: sourceSeries.count) { _, _ in
                refreshDisplayPeaks()
            }
            .onChange(of: sections.map(\.id)) { _, _ in
                refreshDisplayPeaks()
            }
            .onChange(of: peakClips) { _, _ in
                refreshDisplayPeaks()
            }
            .task(id: peaksLoadIdentity) {
                guard hasPeakSource else {
                    sourceSeries = .empty
                    cachedDisplaySeries = .empty
                    return
                }
                if !trackSources.isEmpty {
                    let summed = await WaveformCache.shared.summedMinMax(for: trackSources)
                    if !summed.isEmpty {
                        sourceSeries = summed
                        refreshDisplayPeaks()
                        return
                    }
                }
                if let precomputedSourcePeaks {
                    sourceSeries = .mirrored(precomputedSourcePeaks)
                } else {
                    let peaks = await WaveformCache.shared.summedPeaks(for: trackSources)
                    sourceSeries = .mirrored(peaks)
                }
                refreshDisplayPeaks()
            }
    }

    #if os(macOS)
    @ViewBuilder
    private var scrollBackingLayer: some View {
        // The TimelineView stays mounted (just paused) when playback stops. Swapping it for a
        // bare view on play/pause rebuilds the tiled layer, which blanks until tiles re-render.
        if showsPlayhead {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !resolvedIsPlaying)) { _ in
                scrollBacking(
                    playheadTime: resolvedPlayheadTime(live: resolvedIsPlaying),
                    showsPlayheadSplit: true
                )
            }
        } else {
            scrollBacking(playheadTime: nil, showsPlayheadSplit: false)
        }
    }

    private func scrollBacking(
        playheadTime: TimeInterval?,
        showsPlayheadSplit: Bool
    ) -> LiveSongWaveformScrollBacking {
        LiveSongWaveformScrollBacking(
            contentWidth: contentWidth,
            timelineDuration: safeTimelineDuration,
            mins: cachedDisplaySeries.mins,
            maxes: cachedDisplaySeries.maxes,
            sections: sections,
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
        // Same identity whether playing or paused, so toggling playback never rebuilds the canvas.
        Group {
            if showsPlayhead {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !resolvedIsPlaying)) { _ in
                    let time = resolvedPlayheadTime(live: resolvedIsPlaying)
                    let span = max(0.0001, timelineEnd - timelineStart)
                    let fraction = CGFloat((time - timelineStart) / span)
                    waveformCanvas(tile: tile, playheadFraction: fraction, usesDrawingGroup: false)
                }
            } else {
                waveformCanvas(
                    tile: tile,
                    playheadFraction: nil,
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
                        let isLoopSection = loopSectionIDs.contains(section.id)

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

                        if showsMissingMediaWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.orange)
                                .frame(width: segmentWidth, height: waveformHeight)
                                .offset(x: startX)
                        }
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
                && pixelsPerBeat(contentWidth: contentWidth) >= LiveSetlistWaveformMetrics.minimumBeatTickSpacing
            let showSubdivisions = showBeats
                && pixelsPerBeat(contentWidth: contentWidth) / 2 >= LiveSetlistWaveformMetrics.minimumSubdivisionTickSpacing

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

            let subdivisionLineColor = Color.white.opacity(LiveSetlistWaveformMetrics.subdivisionTickOpacity)
            let beatLineColor = Color.white.opacity(LiveSetlistWaveformMetrics.beatTickOpacity)
            let measureLineColor = Color.white.opacity(LiveSetlistWaveformMetrics.downbeatTickOpacity)
            let grid = showBeats
                ? MeasureTiming.beatGridTimes(
                    duration: safeTimelineDuration,
                    tempoChanges: tempoChanges,
                    timeSignatureChanges: timeSignatureChanges,
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
                : MeasureTiming.BeatGridTimes(beats: [], subdivisions: [])

            if showSubdivisions {
                for time in grid.subdivisions {
                    strokeGridLine(
                        at: time,
                        contentWidth: contentWidth,
                        tileOrigin: tileOrigin,
                        size: size,
                        color: subdivisionLineColor,
                        in: context
                    )
                }
            }

            if showBeats {
                for time in grid.beats {
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

    private func pixelsPerBeat(contentWidth: CGFloat) -> CGFloat {
        let bpm = MeasureTiming.bpmForMeasure(1, tempoChanges: tempoChanges)
        let signature = MeasureTiming.numeratorDenominatorForMeasure(1, changes: timeSignatureChanges)
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
        return CGFloat(beatDuration) * contentWidth / CGFloat(safeTimelineDuration)
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
        context.fill(Path(rect), with: .color(color))
    }

    @ViewBuilder
    private func sectionMappingTargets(playbackIndex: Int, contentWidth: CGFloat) -> some View {
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
                let segmentWidth = max(0, endX - startX)

                Color.clear
                    .frame(width: segmentWidth, height: waveformHeight)
                    .mappableLiveControl(
                        .goToSection(songIndex: playbackIndex, sectionIndex: index),
                        cornerRadius: AppRadius.sm
                    )
                    .offset(x: startX)
            }
        }
        .frame(width: contentWidth, height: waveformHeight, alignment: .leading)
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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !resolvedIsPlaying)) { _ in
            playheadMarker(
                at: resolvedPlayheadTime(live: resolvedIsPlaying),
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

    private func waveformCanvas(
        tile: ClosedRange<CGFloat>,
        playheadFraction: CGFloat?,
        usesDrawingGroup: Bool
    ) -> some View {
        WaveformBarsCanvas(
            bars: [],
            showsEmptyBaseline: isLoadingWaveform || showsFullSourceWaveform,
            fillColor: .white,
            style: .filledEnvelope,
            playheadFraction: playheadFraction,
            usesDrawingGroup: usesDrawingGroup,
            columnMins: cachedDisplaySeries.mins,
            columnMaxes: cachedDisplaySeries.maxes,
            columnContentWidth: contentWidth,
            columnOriginX: tile.lowerBound
        )
    }

    private func refreshDisplayPeaks() {
        guard !sourceSeries.isEmpty else {
            cachedDisplaySeries = .empty
            return
        }

        if showsFullSourceWaveform {
            cachedDisplaySeries = sourceSeries
        } else {
            cachedDisplaySeries = WaveformPeakResampler.timelineMinMax(
                from: sourceSeries,
                fileDuration: fileDuration,
                clips: peakClips,
                timelineDuration: safeTimelineDuration
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
    /// Matches the MIDI-lane space reserved below song waveforms, so the
    /// divider spans the same height as the surrounding song lanes.
    var extraHeight: CGFloat = 0

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    private let markerWidth: CGFloat = 40

    var body: some View {
        let totalHeight = waveformHeight + extraHeight
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
                    .frame(width: max(0, totalHeight - AppSpacing.md), height: markerWidth)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: markerWidth, height: totalHeight)
            .clipped()
    }
}
