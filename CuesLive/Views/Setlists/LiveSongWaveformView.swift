import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
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
    #if os(iOS)
    /// iOS has no resizable split above the setlist, so the height is fixed: a little taller on
    /// iPad, where there's room for it.
    static let defaultWaveformHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 132 : 96
    #else
    static let defaultWaveformHeight: CGFloat = 96
    #endif
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

    /// Height of one MIDI device lane row below the waveform.
    static let midiLaneRowHeight: CGFloat = 18
    static let midiLaneRowSpacing: CGFloat = 3

    static func midiLanesHeight(forRowCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * midiLaneRowHeight + CGFloat(count) * midiLaneRowSpacing
    }

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

    /// Width of a song lane whose waveform snapshot has not loaded yet.
    static let unloadedLaneWidth: CGFloat = 180

    /// Waveform ahead of the playhead.
    static let waveformUnplayedOpacity: CGFloat = 0.32
    /// Waveform the playhead has passed. Brighter than the rest, still translucent.
    static let waveformPlayedOpacity: CGFloat = 0.80

    /// Bar lines. A step down from solid so the waveform stays in front.
    static let downbeatTickOpacity: CGFloat = 0.50
    /// Quarter-note (or meter beat) ticks.
    static let beatTickOpacity: CGFloat = 0.16
    /// Halfway between beats. Fainter than the downbeat.
    static let subdivisionTickOpacity: CGFloat = 0.08
    static let beatGridMaximumDuration: TimeInterval = 10 * 60
    static let minimumBeatTickSpacing: CGFloat = 8
    static let minimumSubdivisionTickSpacing: CGFloat = 6
}

/// Scroll-offset math for zooming the setlist waveform around the playhead.
/// Fixed chrome (padding, headers, badges, spacing) is omitted: it does not
/// change with zoom, so it cancels out of the offset delta.
enum LiveSetlistZoomAnchor {
    static func laneWidth(timelineDuration: TimeInterval?, zoom: CGFloat) -> CGFloat {
        guard let timelineDuration else { return LiveSetlistWaveformMetrics.unloadedLaneWidth }
        return TimelineLayout.contentWidth(for: timelineDuration, zoom: zoom)
    }

    /// Content X of the playhead counting only zoom-scaled lane widths.
    static func scalablePlayheadX(
        precedingLaneWidths: [CGFloat],
        currentLaneWidth: CGFloat,
        playheadTime: TimeInterval,
        timelineDuration: TimeInterval
    ) -> CGFloat {
        let safeDuration = max(timelineDuration, 0.001)
        let clampedTime = min(max(0, playheadTime), safeDuration)
        let playheadX = TimelineLayout.xPosition(
            for: clampedTime,
            duration: safeDuration,
            contentWidth: currentLaneWidth
        )
        return precedingLaneWidths.reduce(0, +) + playheadX
    }

    static func scrollOffsetDelta(
        precedingLaneWidthsBefore: [CGFloat],
        currentLaneWidthBefore: CGFloat,
        precedingLaneWidthsAfter: [CGFloat],
        currentLaneWidthAfter: CGFloat,
        playheadTime: TimeInterval,
        timelineDuration: TimeInterval
    ) -> CGFloat {
        let before = scalablePlayheadX(
            precedingLaneWidths: precedingLaneWidthsBefore,
            currentLaneWidth: currentLaneWidthBefore,
            playheadTime: playheadTime,
            timelineDuration: timelineDuration
        )
        let after = scalablePlayheadX(
            precedingLaneWidths: precedingLaneWidthsAfter,
            currentLaneWidth: currentLaneWidthAfter,
            playheadTime: playheadTime,
            timelineDuration: timelineDuration
        )
        return after - before
    }
}

/// Applies one zoom gesture's scroll correction. Steps in a gesture sum onto the
/// offset captured when the gesture starts, so a batched SwiftUI update still
/// lands on the playhead. A later gesture keeps an unreached target as its base
/// so a clamped correction is not dropped.
struct LiveSetlistZoomScrollSession {
    static let maximumStableAttempts = 8

    private(set) var batchID: Int?
    private(set) var baseOffset: CGFloat?
    private(set) var unclampedTarget: CGFloat?
    private(set) var reachedTarget = false
    private var confirmedContentWidth: CGFloat?
    private var stableRetries = 0

    struct Update: Equatable {
        /// Scroll offset to apply. `nil` leaves the scroll view where it is.
        var offset: CGFloat?
        /// No further correction is pending.
        var isSettled: Bool
    }

    mutating func update(
        batchID: Int?,
        delta: CGFloat,
        actualOffset: CGFloat?,
        minimumOffset: CGFloat,
        maximumOffset: CGFloat,
        contentWidth: CGFloat?,
        allowStable: Bool
    ) -> Update {
        if let batchID {
            guard let actualOffset else { return Update(offset: nil, isSettled: false) }
            noteBatch(batchID, delta: delta, actualOffset: actualOffset)
            let offset = resolve(
                actualOffset: actualOffset,
                minimumOffset: minimumOffset,
                maximumOffset: maximumOffset,
                contentWidth: contentWidth,
                allowStable: allowStable
            )
            return Update(offset: offset, isSettled: reachedTarget)
        }

        guard unclampedTarget != nil, let actualOffset else {
            return Update(offset: nil, isSettled: true)
        }
        let offset = resolve(
            actualOffset: actualOffset,
            minimumOffset: minimumOffset,
            maximumOffset: maximumOffset,
            contentWidth: contentWidth,
            allowStable: allowStable
        )
        let settled = reachedTarget
        if reachedTarget {
            reset()
        }
        return Update(offset: offset, isSettled: settled)
    }

    private mutating func noteBatch(_ batchID: Int, delta: CGFloat, actualOffset: CGFloat) {
        if self.batchID != batchID {
            if let unclampedTarget, !reachedTarget {
                baseOffset = unclampedTarget
            } else {
                baseOffset = actualOffset
            }
            self.batchID = batchID
            reachedTarget = false
            confirmedContentWidth = nil
            stableRetries = 0
        }
        guard let baseOffset else { return }
        let target = baseOffset + delta
        guard unclampedTarget != target else { return }
        unclampedTarget = target
        reachedTarget = false
        confirmedContentWidth = nil
        stableRetries = 0
    }

    private mutating func resolve(
        actualOffset: CGFloat,
        minimumOffset: CGFloat,
        maximumOffset: CGFloat,
        contentWidth: CGFloat?,
        allowStable: Bool
    ) -> CGFloat? {
        guard let target = unclampedTarget, !reachedTarget else { return nil }
        let upper = max(minimumOffset, maximumOffset)
        let clamped = min(max(target, minimumOffset), upper)
        let widthStable = allowStable && contentWidth != nil && confirmedContentWidth == contentWidth
        if allowStable, let contentWidth {
            confirmedContentWidth = contentWidth
            stableRetries += 1
        }
        let atTarget = abs(clamped - target) <= 1
        let alreadyThere = abs(actualOffset - clamped) <= 0.5
        let gaveUp = stableRetries > Self.maximumStableAttempts
        if alreadyThere && (atTarget || widthStable || gaveUp) {
            reachedTarget = true
            return nil
        }
        if gaveUp {
            reachedTarget = true
        }
        return alreadyThere ? nil : clamped
    }

    private mutating func reset() {
        batchID = nil
        baseOffset = nil
        unclampedTarget = nil
        reachedTarget = false
        confirmedContentWidth = nil
        stableRetries = 0
    }
}

/// Read-only strip below the waveform showing one MIDI device's cue points as
/// small dots along the timeline — the setlist view's counterpart to the song
/// editor's fully-interactive `MIDILaneView`.
struct LiveMIDIEventLaneView: View {
    let contentWidth: CGFloat
    let timelineDuration: TimeInterval
    let deviceName: String
    let events: [MIDIEvent]

    private static let dotSize: CGFloat = 6

    private var safeDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(Color.white.opacity(0.06))

            ForEach(events) { event in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .position(
                        x: TimelineLayout.xPosition(
                            for: event.timelineSeconds,
                            duration: safeDuration,
                            contentWidth: contentWidth
                        ),
                        y: LiveSetlistWaveformMetrics.midiLaneRowHeight / 2
                    )
            }

            Text(deviceName.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(AppColors.surfaceElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(.leading, 3)
                .padding(.top, 1)
        }
        .frame(width: contentWidth, height: LiveSetlistWaveformMetrics.midiLaneRowHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .allowsHitTesting(false)
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

/// How the setlist split pane should react when MIDI lanes appear after the
/// divider has already been placed. `VSplitView` keeps that first height, so a
/// later lane row is clipped until the measured waveform height shrinks to
/// make room or the pane's minimum is raised long enough for the divider to move.
enum LiveSetlistWaveformPaneAdjustment {
    struct Measurement: Equatable {
        var assignedHeight: CGFloat
        var midiOverhead: CGFloat
        var storedWaveformHeight: CGFloat
        var previousAssignedHeight: CGFloat?
        var previousMIDIOverhead: CGFloat?
        /// The pane did not grow for the new lanes. Fit them into the height it has.
        var forceFit: Bool = false
    }

    struct Decision: Equatable {
        /// `nil` leaves the current waveform height alone so a pending pane
        /// resize can keep the saved waveform size.
        var waveformHeight: CGFloat?
        var persistWaveformHeight: Bool
    }

    static func decision(for measurement: Measurement) -> Decision {
        let fitted = LiveSetlistWaveformMetrics.clampedWaveformHeight(
            measurement.assignedHeight - measurement.midiOverhead
        )
        let isInitial = measurement.previousMIDIOverhead == nil
        let overheadStable: Bool
        let paneChanged: Bool
        // A divider move only counts as a user resize once the pane has already
        // held the saved waveform. The first layouts often settle from the
        // minimum height up to the real one.
        let previousFitsSavedWaveform: Bool
        if let previousMIDIOverhead = measurement.previousMIDIOverhead {
            overheadStable = abs(measurement.midiOverhead - previousMIDIOverhead) < 0.5
            let previousAssigned = measurement.previousAssignedHeight ?? measurement.assignedHeight
            paneChanged = abs(measurement.assignedHeight - previousAssigned) > 0.5
            previousFitsSavedWaveform = previousAssigned + 0.5
                >= measurement.storedWaveformHeight + previousMIDIOverhead
        } else {
            overheadStable = false
            paneChanged = false
            previousFitsSavedWaveform = false
        }
        let userAdjusted = paneChanged && overheadStable && previousFitsSavedWaveform
        let paneFitsSavedWaveform = measurement.assignedHeight + 0.5
            >= measurement.storedWaveformHeight + measurement.midiOverhead
        let apply = userAdjusted || paneFitsSavedWaveform || measurement.forceFit
        guard apply else {
            return Decision(waveformHeight: nil, persistWaveformHeight: false)
        }
        let persist = userAdjusted || (isInitial && paneFitsSavedWaveform)
        return Decision(waveformHeight: fitted, persistWaveformHeight: persist)
    }

    /// Minimum content height that forces the split divider down when lanes
    /// appear. `nil` uses the normal drag floor.
    static func reservedPaneHeight(
        storedWaveformHeight: CGFloat,
        midiOverhead: CGFloat,
        isReserving: Bool
    ) -> CGFloat? {
        guard isReserving, midiOverhead > 0.5 else { return nil }
        return storedWaveformHeight + midiOverhead
    }
}

#if os(macOS)
/// Gives the top pane of a `VSplitView` (see
/// `LivePlaybackView.playbackMainSection`) a reasonable initial/minimum
/// height. The actual live-resize measurement happens inside
/// `LiveSetlistWaveformScrollView` itself (it self-measures rather than
/// having an ancestor derive its height and republish it downward, which
/// only works if every view in between is already flexible).
struct LiveSetlistWaveformResizablePane<Content: View>: View {
    var maxMIDILaneCount: Int = 0
    @ViewBuilder let content: () -> Content

    @AppStorage(LiveSetlistWaveformMetrics.appStorageKey)
    private var storedWaveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeightStorageValue
    /// Briefly holds the pane open at the saved waveform height plus MIDI rows.
    /// The split view ignores a later `idealHeight`, but it will honor a minimum
    /// that's taller than the current divider position.
    @State private var reservesMIDILaneHeight = false
    @State private var midiReserveGeneration = 0

    private var overheadHeight: CGFloat {
        LiveSetlistWaveformMetrics.midiLanesHeight(forRowCount: maxMIDILaneCount)
    }

    private var storedContentHeight: CGFloat {
        LiveSetlistWaveformMetrics.waveformHeight(fromStorage: storedWaveformHeight)
    }

    private var minimumPaneHeight: CGFloat {
        let base = LiveSetlistWaveformMetrics.minimumWaveformHeight + overheadHeight
        guard let reserved = LiveSetlistWaveformPaneAdjustment.reservedPaneHeight(
            storedWaveformHeight: storedContentHeight,
            midiOverhead: overheadHeight,
            isReserving: reservesMIDILaneHeight
        ) else {
            return base
        }
        return max(base, reserved)
    }

    var body: some View {
        content()
            .frame(
                minHeight: minimumPaneHeight,
                idealHeight: storedContentHeight + overheadHeight,
                maxHeight: LiveSetlistWaveformMetrics.maximumWaveformHeight + overheadHeight
            )
            // Keeps the VSplitView divider from sitting flush against the waveform.
            .padding(.bottom, AppSpacing.xs)
            .animation(.none, value: reservesMIDILaneHeight)
            .animation(.none, value: overheadHeight)
            .onAppear {
                reserveSpaceForMIDILanes()
            }
            .onChange(of: overheadHeight) { _, _ in
                reserveSpaceForMIDILanes()
            }
    }

    private func reserveSpaceForMIDILanes() {
        guard overheadHeight > 0.5 else { return }
        midiReserveGeneration += 1
        let generation = midiReserveGeneration
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            reservesMIDILaneHeight = true
        }
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard generation == midiReserveGeneration else { return }
            var clear = Transaction()
            clear.disablesAnimations = true
            withTransaction(clear) {
                reservesMIDILaneHeight = false
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

struct LiveSetlistWaveformScrollView: View {
    let timelineItems: [LiveSetlistTimelineItem]
    let currentPlaybackIndex: Int
    let waveformSnapshotForSongID: (UUID) -> LiveSongWaveformSnapshot?
    let ensureWaveformSnapshotForSongID: (UUID) -> Void
    /// Songs with missing audio get a caution icon in each section.
    var songHasMissingMedia: (UUID) -> Bool = { _ in false }
    let playheadTimeProvider: () -> TimeInterval
    let isPlayingProvider: () -> Bool
    /// Observed while stopped/paused so the playhead moves on seek/section tap.
    var idlePlayheadTime: TimeInterval? = nil
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    let onSeek: (TimeInterval) -> Void
    let onCueSection: (SongSection) -> Void
    var onOverlapBadgeTapped: ((Int) -> Void)?
    /// When set, tapping a non-current song lane jumps to that song, at the tapped section's start when one was hit.
    var onSelectSong: ((Int, TimeInterval?) -> Void)?
    /// Largest MIDI device lane count across the setlist's songs, so every
    /// song's row reserves the same height and switching songs doesn't jump.
    var maxMIDILaneCount: Int = 0

    @Environment(InputMappingController.self) private var mapping

    @AppStorage(LiveSetlistWaveformMetrics.horizontalZoomAppStorageKey)
    private var storedHorizontalZoom = LiveSetlistWaveformMetrics.defaultHorizontalZoomStorageValue

    #if os(macOS)
    // Self-measured (see the trailing `background` in `body`) rather than read
    // from an ancestor's environment: an ancestor would need to already be
    // flexible to observe VSplitView's live-resized height, but every view
    // between here and the split pane has its own fixed intrinsic size.
    @AppStorage(LiveSetlistWaveformMetrics.appStorageKey)
    private var storedWaveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeightStorageValue
    @State private var waveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeight
    @State private var assignedPaneHeight: CGFloat = 0
    /// `-1` until the first pane measurement. `0` is a real "no MIDI lanes" overhead.
    @State private var measuredMIDIOverhead: CGFloat = -1
    @State private var isMIDILaneRevealScheduled = false
    #else
    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight
    #endif

    @State private var isFollowing = true
    @State private var isUserScrolling = false
    @State private var playheadViewportX: CGFloat?
    @State private var viewportWidth: CGFloat = 1
    @State private var horizontalZoom = LiveSetlistWaveformMetrics.defaultHorizontalZoom
    @State private var pinchStartZoom: CGFloat?
    /// Summed playhead shift for the open zoom gesture. Cleared once the scroll
    /// view has had a chance to apply it.
    @State private var zoomBatch: ZoomBatch?
    @State private var zoomGestureID = 0
    @State private var isZoomGesturing = false

    private struct ZoomBatch: Equatable {
        var id: Int
        var delta: CGFloat
    }

    private let laneSpacing: CGFloat = 24
    private static let zoomAdjustmentStep: CGFloat = 0.25

    private var midiLanesExtraHeight: CGFloat {
        LiveSetlistWaveformMetrics.midiLanesHeight(forRowCount: maxMIDILaneCount)
    }

    private var laneHeight: CGFloat {
        LiveSetlistWaveformMetrics.laneHeight(for: waveformHeight) + midiLanesExtraHeight
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
                .background(alignment: .topLeading) {
                    LiveSetlistZoomScrollAdjuster(
                        batchID: zoomBatch?.id,
                        delta: zoomBatch?.delta ?? 0
                    )
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .defaultScrollAnchor(.leading)
            // Keep a single scrollTargetBehavior instance so toggling follow does not
            // recreate the ScrollView (which would jump to defaultScrollAnchor).
            .scrollTargetBehavior(LiveSetlistFollowScrollTargetBehavior(isFollowing: isFollowing))
            .coordinateSpace(name: LiveSetlistWaveformMetrics.scrollCoordinateSpaceName)
            .modifier(LiveSetlistFollowUserScrollDetector(
                isFollowing: $isFollowing,
                isUserScrolling: $isUserScrolling,
                suspendsUserScrollTracking: isZoomGesturing
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
                if scrolling {
                    // Playhead updates are ignored mid-scroll, so the last value goes stale.
                    // Drop it; relatching on it when the scroll ends would snap back to follow.
                    playheadViewportX = nil
                } else {
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
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        LiveSetlistFollowScrollDriver(date: context.date) {
                            guard isPlayingProvider() else { return }
                            scrollToFollowPlayhead(proxy, requirePlaying: true)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .simultaneousGesture(horizontalPinchGesture)
        #else
        .modifier(LiveSetlistTouchPinchModifier(
            fallbackGesture: horizontalPinchGesture,
            onChanged: pinchChanged,
            onEnded: pinchEnded
        ))
        #endif
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size.width, initial: true) { _, width in
                        viewportWidth = max(width, 1)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .frame(
            minHeight: LiveSetlistWaveformMetrics.minimumWaveformHeight + midiLanesExtraHeight,
            maxHeight: LiveSetlistWaveformMetrics.maximumWaveformHeight + midiLanesExtraHeight,
            alignment: .top
        )
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size.height, initial: true) { _, height in
                        updateWaveformHeight(forAssignedHeight: height)
                    }
            }
        }
        .onChange(of: midiLanesExtraHeight) { _, _ in
            scheduleMIDILaneReveal()
        }
        .environment(\.liveSetlistWaveformHeight, waveformHeight)
        #else
        .frame(height: laneHeight)
        #endif
        .animation(.none, value: waveformHeight)
        .animation(.none, value: horizontalZoom)
        .onAppear {
            horizontalZoom = LiveSetlistWaveformMetrics.horizontalZoom(fromStorage: storedHorizontalZoom)
            #if os(macOS)
            waveformHeight = LiveSetlistWaveformMetrics.waveformHeight(fromStorage: storedWaveformHeight)
            scheduleMIDILaneReveal()
            #endif
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

    #if os(macOS)
    private func updateWaveformHeight(forAssignedHeight assignedHeight: CGFloat, forceFit: Bool = false) {
        guard assignedHeight > 1 else { return }
        let overhead = midiLanesExtraHeight
        let decision = LiveSetlistWaveformPaneAdjustment.decision(
            for: .init(
                assignedHeight: assignedHeight,
                midiOverhead: overhead,
                storedWaveformHeight: LiveSetlistWaveformMetrics.waveformHeight(fromStorage: storedWaveformHeight),
                previousAssignedHeight: measuredMIDIOverhead < 0 ? nil : assignedPaneHeight,
                previousMIDIOverhead: measuredMIDIOverhead < 0 ? nil : measuredMIDIOverhead,
                forceFit: forceFit
            )
        )
        assignedPaneHeight = assignedHeight
        measuredMIDIOverhead = overhead

        if let fitted = decision.waveformHeight, fitted != waveformHeight {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                waveformHeight = fitted
            }
        }
        if decision.persistWaveformHeight, let fitted = decision.waveformHeight {
            storedWaveformHeight = LiveSetlistWaveformMetrics.storageValue(forHeight: fitted)
        } else if decision.waveformHeight == nil {
            // Divider hasn't moved for these lanes yet. Give the pane's temporary
            // minimum a layout pass, then fit into whatever height it actually got.
            scheduleMIDILaneReveal()
        }
    }

    private func scheduleMIDILaneReveal(attempt: Int = 0) {
        guard midiLanesExtraHeight > 0.5, !isMIDILaneRevealScheduled, attempt < 5 else { return }
        isMIDILaneRevealScheduled = true
        let overhead = midiLanesExtraHeight
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            isMIDILaneRevealScheduled = false
            guard abs(midiLanesExtraHeight - overhead) < 0.5 else {
                scheduleMIDILaneReveal()
                return
            }
            // The pane measurement arrives on the first layout pass, which can
            // be after this wait. Try again instead of leaving the lanes clipped.
            guard assignedPaneHeight > 1 else {
                scheduleMIDILaneReveal(attempt: attempt + 1)
                return
            }
            let fitted = LiveSetlistWaveformMetrics.clampedWaveformHeight(assignedPaneHeight - overhead)
            guard fitted + 0.5 < waveformHeight else { return }
            updateWaveformHeight(forAssignedHeight: assignedPaneHeight, forceFit: true)
        }
    }
    #endif

    @ViewBuilder
    private func timelineItemView(_ item: LiveSetlistTimelineItem) -> some View {
        switch item {
        case .header(_, let title):
            SetlistWaveformHeaderMarker(title: title, extraHeight: midiLanesExtraHeight)
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
        VStack(spacing: 0) {
            SetlistTransitionBadge(
                transition: transition,
                onTap: transition == .overlap
                    ? { onOverlapBadgeTapped?(playbackIndex) }
                    : nil
            )
            .frame(height: waveformHeight)
            if midiLanesExtraHeight > 0 {
                Color.clear.frame(height: midiLanesExtraHeight)
            }
        }
    }

    private var horizontalPinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged(pinchChanged)
            .onEnded { _ in pinchEnded() }
    }

    private func pinchChanged(_ scale: CGFloat) {
        let starting = pinchStartZoom == nil
        if starting {
            pinchStartZoom = horizontalZoom
            // Follow recenters on a timer. Hold it off for the whole pinch, including
            // the first events whose scale has not moved the playhead yet.
            beginZoomGesture()
        }
        guard let pinchStartZoom else { return }
        let oldZoom = horizontalZoom
        let newZoom = LiveSetlistWaveformMetrics.clampedHorizontalZoom(pinchStartZoom * scale)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            anchorZoom(from: oldZoom, to: newZoom)
            horizontalZoom = newZoom
        }
    }

    private func pinchEnded() {
        pinchStartZoom = nil
        persistHorizontalZoom()
        endZoomGesture()
    }

    private func setHorizontalZoom(_ proposed: CGFloat) {
        let oldZoom = horizontalZoom
        let newZoom = LiveSetlistWaveformMetrics.clampedHorizontalZoom(proposed)
        guard newZoom != oldZoom else { return }
        let beganHere = !isZoomGesturing
        anchorZoom(from: oldZoom, to: newZoom)
        horizontalZoom = newZoom
        persistHorizontalZoom()
        if beganHere {
            endZoomGesture()
        }
    }

    private func beginZoomGesture() {
        zoomGestureID += 1
        isZoomGesturing = true
    }

    /// Shifts the scroll offset by the same amount the playhead's content X moves.
    /// Steps accumulate on the gesture's batch so one SwiftUI update still includes
    /// every scale change.
    private func anchorZoom(from oldZoom: CGFloat, to newZoom: CGFloat) {
        guard oldZoom != newZoom else { return }
        let time = resolvedPlayheadTime()
        let step = scalablePlayheadX(zoom: newZoom, time: time)
            - scalablePlayheadX(zoom: oldZoom, time: time)
        guard step != 0 else { return }
        if !isZoomGesturing {
            beginZoomGesture()
        }
        if zoomBatch?.id != zoomGestureID {
            zoomBatch = ZoomBatch(id: zoomGestureID, delta: step)
        } else if var batch = zoomBatch {
            batch.delta += step
            zoomBatch = batch
        }
    }

    private func endZoomGesture() {
        guard isZoomGesturing else { return }
        let gestureID = zoomGestureID
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard zoomGestureID == gestureID else { return }
            zoomBatch = nil
            isZoomGesturing = false
        }
    }

    private func resolvedPlayheadTime() -> TimeInterval {
        if isPlayingProvider() {
            return playheadTimeProvider()
        }
        if let idlePlayheadTime {
            return idlePlayheadTime
        }
        return playheadTimeProvider()
    }

    private func scalablePlayheadX(zoom: CGFloat, time: TimeInterval) -> CGFloat {
        var preceding: [CGFloat] = []
        for item in timelineItems {
            guard case .song(let songID, let playbackIndex, _) = item else { continue }
            let duration = waveformSnapshotForSongID(songID)?.timelineDuration
            let width = LiveSetlistZoomAnchor.laneWidth(timelineDuration: duration, zoom: zoom)
            if playbackIndex == currentPlaybackIndex {
                return LiveSetlistZoomAnchor.scalablePlayheadX(
                    precedingLaneWidths: preceding,
                    currentLaneWidth: width,
                    playheadTime: time,
                    timelineDuration: duration ?? 0
                )
            }
            preceding.append(width)
        }
        return 0
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
            guard self.isFollowing, !self.isZoomGesturing else { return }
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
        let laneSnapshot = waveformSnapshotForSongID(songID)

        Group {
            if let snapshot = laneSnapshot {
                waveformLane(snapshot: snapshot, playbackIndex: playbackIndex, isCurrent: isCurrent)
            } else {
                LiveSetlistWaveformLanePlaceholder(isCurrent: isCurrent)
                    .frame(minHeight: waveformHeight + midiLanesExtraHeight, alignment: .top)
                    .task(id: songID) {
                        ensureWaveformSnapshotForSongID(songID)
                    }
            }
        }
        .modifier(NonCurrentSongSelectTapModifier(
            isEnabled: !isCurrent && onSelectSong != nil && !mapping.showsLiveHighlights,
            contentWidth: laneSnapshot.map { laneContentWidth(for: $0) } ?? 0,
            duration: laneSnapshot?.timelineDuration ?? 0,
            sections: laneSnapshot?.sections ?? [],
            onSelect: { onSelectSong?(playbackIndex, $0) }
        ))
    }

    @ViewBuilder
    private func waveformLane(
        snapshot: LiveSongWaveformSnapshot,
        playbackIndex: Int,
        isCurrent: Bool
    ) -> some View {
        let laneContentWidth = laneContentWidth(for: snapshot)

        VStack(alignment: .leading, spacing: LiveSetlistWaveformMetrics.midiLaneRowSpacing) {
            LiveSongWaveformView(
                contentWidth: laneContentWidth,
                trackSources: snapshot.trackSources,
                fileDuration: snapshot.fileDuration,
                timelineDuration: snapshot.timelineDuration,
                sections: snapshot.sections,
                peakClips: snapshot.peakClips,
                loopSectionIDs: snapshot.loopSectionIDs,
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
                showsMissingMediaWarning: songHasMissingMedia(snapshot.songID),
                idlePlayheadTime: isCurrent ? idlePlayheadTime : nil,
                playheadTimeProvider: isCurrent ? playheadTimeProvider : nil,
                isPlayingProvider: isCurrent ? isPlayingProvider : nil,
                onSeek: onSeek,
                onCueSection: onCueSection,
                playbackIndex: playbackIndex
            )

            ForEach(snapshot.midiLanes) { lane in
                LiveMIDIEventLaneView(
                    contentWidth: laneContentWidth,
                    timelineDuration: snapshot.timelineDuration,
                    deviceName: lane.deviceName,
                    events: lane.events
                )
            }
        }
        // Songs with fewer MIDI lanes still occupy the tallest lane's height,
        // so every waveform stays on the same vertical line.
        .frame(minHeight: waveformHeight + midiLanesExtraHeight, alignment: .top)
        .opacity(isCurrent ? 1 : 0.72)
    }
}

private struct LiveSetlistWaveformLanePlaceholder: View {
    let isCurrent: Bool

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    var body: some View {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.backgroundPrimary)
                .frame(width: LiveSetlistWaveformMetrics.unloadedLaneWidth, height: waveformHeight)
            .opacity(isCurrent ? 1 : 0.72)
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
    }
}

/// Tapping a lane for a song that isn't cued selects it; a tap inside a section also
/// reports that section's start so playback lands there.
private struct NonCurrentSongSelectTapModifier: ViewModifier {
    let isEnabled: Bool
    let contentWidth: CGFloat
    let duration: TimeInterval
    let sections: [SongSection]
    let onSelect: (TimeInterval?) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            onSelect(sectionStart(atX: event.location.x))
                        }
                )
        } else {
            content
        }
    }

    private func sectionStart(atX x: CGFloat) -> TimeInterval? {
        guard contentWidth > 0, duration > 0, !sections.isEmpty else { return nil }
        let time = TimelineLayout.time(at: x, duration: duration, contentWidth: contentWidth)
        let hit = sections.first { time >= $0.timelineStartSeconds && time < $0.timelineEndSeconds }
            ?? sections.last.flatMap { time >= $0.timelineStartSeconds && time <= $0.timelineEndSeconds ? $0 : nil }
        return hit?.timelineStartSeconds
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
    /// Programmatic playhead-anchored zoom also moves the scroll view.
    var suspendsUserScrollTracking = false

    func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, newPhase in
                    guard !suspendsUserScrollTracking else { return }
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
                            guard !suspendsUserScrollTracking else { return }
                            isUserScrolling = true
                            isFollowing = false
                        }
                        .onEnded { _ in
                            guard !suspendsUserScrollTracking else { return }
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

#if os(iOS)
/// Pinch-to-zoom on the live waveform for touch screens. A SwiftUI pinch attached around the
/// horizontal ScrollView loses two-finger touches to the scroll view's own pan recognizer, so on
/// iOS 18+ a UIKit pinch recognizer runs alongside scrolling instead. iOS 17 keeps the SwiftUI
/// gesture.
private struct LiveSetlistTouchPinchModifier<Fallback: Gesture>: ViewModifier {
    let fallbackGesture: Fallback
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(LiveSetlistPinchRecognizer(onChanged: onChanged, onEnded: onEnded))
        } else {
            content.simultaneousGesture(fallbackGesture)
        }
    }
}

@available(iOS 18.0, *)
private struct LiveSetlistPinchRecognizer: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.scale)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Let pinch run alongside the scroll view's pan and the lanes' tap and drag gestures.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif

/// Shifts the waveform scroll view so a zoom keeps the playhead under the same
/// screen position. SwiftUI's scroll view otherwise keeps its point offset while
/// the lanes grow, which slides the playhead sideways.
private struct LiveSetlistZoomScrollAdjuster: View {
    var batchID: Int?
    var delta: CGFloat

    var body: some View {
        #if os(macOS)
        LiveSetlistZoomScrollAdjusterMac(batchID: batchID, delta: delta)
        #else
        LiveSetlistZoomScrollAdjusterIOS(batchID: batchID, delta: delta)
        #endif
    }
}

private struct LiveSetlistZoomScrollMetrics {
    var offset: CGFloat
    var minimum: CGFloat
    var maximum: CGFloat
    var contentWidth: CGFloat
}

/// Retry loop shared by the macOS and iOS scroll adjusters.
private final class LiveSetlistZoomScrollDriver {
    private var session = LiveSetlistZoomScrollSession()
    private var batchID: Int?
    private var delta: CGFloat = 0
    private var retryScheduled = false
    private var retryCount = 0
    private var isApplying = false

    var needsLayoutPass: Bool {
        batchID != nil || session.unclampedTarget != nil
    }

    func sync(
        batchID: Int?,
        delta: CGFloat,
        readMetrics: @escaping () -> LiveSetlistZoomScrollMetrics?,
        setOffset: @escaping (CGFloat) -> Void
    ) {
        if batchID != self.batchID || delta != self.delta {
            retryCount = 0
        }
        self.batchID = batchID
        self.delta = delta
        let settled = apply(allowStable: batchID == nil, readMetrics: readMetrics, setOffset: setOffset)
        if !settled {
            scheduleRetry(readMetrics: readMetrics, setOffset: setOffset)
        }
    }

    func applyFromLayout(
        readMetrics: () -> LiveSetlistZoomScrollMetrics?,
        setOffset: (CGFloat) -> Void
    ) {
        guard needsLayoutPass else { return }
        apply(allowStable: batchID == nil, readMetrics: readMetrics, setOffset: setOffset)
    }

    private func scheduleRetry(
        readMetrics: @escaping () -> LiveSetlistZoomScrollMetrics?,
        setOffset: @escaping (CGFloat) -> Void
    ) {
        guard !retryScheduled, retryCount < LiveSetlistZoomScrollSession.maximumStableAttempts else { return }
        retryScheduled = true
        retryCount += 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            let settled = self.apply(
                allowStable: self.batchID == nil,
                readMetrics: readMetrics,
                setOffset: setOffset
            )
            if !settled {
                self.scheduleRetry(readMetrics: readMetrics, setOffset: setOffset)
            }
        }
    }

    @discardableResult
    private func apply(
        allowStable: Bool,
        readMetrics: () -> LiveSetlistZoomScrollMetrics?,
        setOffset: (CGFloat) -> Void
    ) -> Bool {
        guard !isApplying else { return session.reachedTarget }
        guard let metrics = readMetrics() else {
            return batchID == nil && session.unclampedTarget == nil
        }
        isApplying = true
        let update = session.update(
            batchID: batchID,
            delta: delta,
            actualOffset: metrics.offset,
            minimumOffset: metrics.minimum,
            maximumOffset: metrics.maximum,
            contentWidth: metrics.contentWidth,
            allowStable: allowStable
        )
        if let offset = update.offset {
            setOffset(offset)
        }
        isApplying = false
        return update.isSettled
    }
}

#if os(macOS)
private struct LiveSetlistZoomScrollAdjusterMac: NSViewRepresentable {
    var batchID: Int?
    var delta: CGFloat

    func makeNSView(context: Context) -> LiveSetlistZoomScrollAdjusterMacView {
        let view = LiveSetlistZoomScrollAdjusterMacView()
        view.sync(batchID: batchID, delta: delta)
        return view
    }

    func updateNSView(_ nsView: LiveSetlistZoomScrollAdjusterMacView, context: Context) {
        nsView.sync(batchID: batchID, delta: delta)
    }
}

private final class LiveSetlistZoomScrollAdjusterMacView: NSView {
    private let driver = LiveSetlistZoomScrollDriver()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        driver.applyFromLayout(
            readMetrics: { self.scrollMetrics() },
            setOffset: { self.setOffset($0) }
        )
    }

    func sync(batchID: Int?, delta: CGFloat) {
        driver.sync(
            batchID: batchID,
            delta: delta,
            readMetrics: { [weak self] in self?.scrollMetrics() },
            setOffset: { [weak self] in self?.setOffset($0) }
        )
    }

    private func scrollMetrics() -> LiveSetlistZoomScrollMetrics? {
        guard let scrollView = enclosingScrollView else { return nil }
        let clip = scrollView.contentView
        let contentWidth = scrollView.documentView?.frame.width ?? clip.bounds.width
        let maximum = max(0, contentWidth - clip.bounds.width)
        return LiveSetlistZoomScrollMetrics(
            offset: clip.bounds.origin.x,
            minimum: 0,
            maximum: maximum,
            contentWidth: contentWidth
        )
    }

    private func setOffset(_ x: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        guard abs(clip.bounds.origin.x - x) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        scrollView.reflectScrolledClipView(clip)
    }
}
#else
private struct LiveSetlistZoomScrollAdjusterIOS: UIViewRepresentable {
    var batchID: Int?
    var delta: CGFloat

    func makeUIView(context: Context) -> LiveSetlistZoomScrollAdjusterIOSView {
        let view = LiveSetlistZoomScrollAdjusterIOSView()
        view.sync(batchID: batchID, delta: delta)
        return view
    }

    func updateUIView(_ uiView: LiveSetlistZoomScrollAdjusterIOSView, context: Context) {
        uiView.sync(batchID: batchID, delta: delta)
    }
}

private final class LiveSetlistZoomScrollAdjusterIOSView: UIView {
    private let driver = LiveSetlistZoomScrollDriver()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        driver.applyFromLayout(
            readMetrics: { self.scrollMetrics() },
            setOffset: { self.setOffset($0) }
        )
    }

    func sync(batchID: Int?, delta: CGFloat) {
        driver.sync(
            batchID: batchID,
            delta: delta,
            readMetrics: { [weak self] in self?.scrollMetrics() },
            setOffset: { [weak self] in self?.setOffset($0) }
        )
    }

    private func scrollMetrics() -> LiveSetlistZoomScrollMetrics? {
        guard let scrollView = enclosingScrollView() else { return nil }
        let minimum = -scrollView.adjustedContentInset.left
        let maximum = max(
            minimum,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )
        return LiveSetlistZoomScrollMetrics(
            offset: scrollView.contentOffset.x,
            minimum: minimum,
            maximum: maximum,
            contentWidth: scrollView.contentSize.width
        )
    }

    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    private func setOffset(_ x: CGFloat) {
        guard let scrollView = enclosingScrollView() else { return }
        guard abs(scrollView.contentOffset.x - x) > 0.5 else { return }
        scrollView.setContentOffset(CGPoint(x: x, y: scrollView.contentOffset.y), animated: false)
    }
}
#endif
