import SwiftUI

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
