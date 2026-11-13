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
    var storedHorizontalZoom = LiveSetlistWaveformMetrics.defaultHorizontalZoomStorageValue

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    @State var scrollModel = LiveSetlistScrollModel()
    @State var horizontalZoom = LiveSetlistWaveformMetrics.defaultHorizontalZoom
    @State var pinchStartZoom: CGFloat?

    private let laneSpacing: CGFloat = 24

    private var laneIndices: Set<Int> {
        Set(timelineItems.compactMap { item in
            if case .song(_, let playbackIndex, _) = item { return playbackIndex }
            return nil
        })
    }

    private var laneCanvas: LiveSetlistLaneCanvas {
        LiveSetlistLaneCanvas(
            songs: timelineItems.compactMap { item in
                guard case .song(let songID, let playbackIndex, _) = item,
                      let snapshot = waveformSnapshotForSongID(songID) else { return nil }
                return LiveSetlistLaneCanvas.Song(
                    index: playbackIndex,
                    snapshot: snapshot,
                    isCurrent: playbackIndex == currentPlaybackIndex
                )
            },
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase
        )
    }

    private var midiLanesExtraHeight: CGFloat {
        LiveSetlistWaveformMetrics.midiLanesHeight(forRowCount: maxMIDILaneCount)
    }

    private var laneHeight: CGFloat {
        LiveSetlistWaveformMetrics.laneHeight(for: waveformHeight) + midiLanesExtraHeight
    }

    var body: some View {
        LiveSetlistScrollHost(
            model: scrollModel,
            currentIndex: currentPlaybackIndex,
            playheadTime: playheadTimeProvider,
            isPlaying: isPlayingProvider,
            idlePlayheadTime: idlePlayheadTime,
            laneIndices: laneIndices,
            canvas: laneCanvas,
            onPinchChanged: pinchChanged,
            onPinchEnded: pinchEnded,
            onWheelZoom: zoomHorizontally(by:)
        ) {
            stripContent
        }
        .frame(maxWidth: .infinity)
        .frame(height: laneHeight)
        .animation(.none, value: waveformHeight)
        .animation(.none, value: horizontalZoom)
        .onAppear {
            horizontalZoom = LiveSetlistWaveformMetrics.horizontalZoom(fromStorage: storedHorizontalZoom)
        }
        .accessibilityAdjustableAction(adjustHorizontalZoom)
        .focusedSceneValue(\.timelineZoomActions, horizontalZoomActions)
    }

    /// The song lanes, laid out once across the whole setlist. The scroll host moves them.
    private var stripContent: some View {
        HStack(alignment: .center, spacing: laneSpacing) {
            ForEach(timelineItems) { item in
                timelineItemView(item)
            }
        }
        .padding(.leading, AppSpacing.md)
        .padding(.vertical, 2)
        .fixedSize(horizontal: true, vertical: false)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            scrollModel.setContentWidth(width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .coordinateSpace(name: LiveSetlistWaveformMetrics.scrollCoordinateSpaceName)
        #if os(macOS)
        .simultaneousGesture(horizontalPinchGesture)
        #endif
    }

    @ViewBuilder
    private func timelineItemView(_ item: LiveSetlistTimelineItem) -> some View {
        switch item {
        case .header(_, let title):
            SetlistWaveformHeaderMarker(title: title, extraHeight: midiLanesExtraHeight)

        case .song(let songID, let playbackIndex, let transitionAfter):
            HStack(alignment: .center, spacing: laneSpacing) {
                songLane(songID: songID, playbackIndex: playbackIndex)

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

    private func laneContentWidth(for snapshot: LiveSongWaveformSnapshot) -> CGFloat {
        TimelineLayout.contentWidth(for: snapshot.timelineDuration, zoom: horizontalZoom)
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
                timelineDuration: snapshot.timelineDuration,
                sections: snapshot.sections,
                loopSectionIDs: snapshot.loopSectionIDs,
                isInteractive: isCurrent,
                showsMissingMediaWarning: songHasMissingMedia(snapshot.songID),
                onSeek: onSeek,
                onCueSection: onCueSection,
                playbackIndex: playbackIndex
            )
            .onGeometryChange(for: LiveSetlistScrollModel.Lane.self) { proxy in
                LiveSetlistScrollModel.Lane(
                    frame: proxy.frame(in: .named(LiveSetlistWaveformMetrics.scrollCoordinateSpaceName)),
                    duration: snapshot.timelineDuration
                )
            } action: { lane in
                scrollModel.setLane(lane, at: playbackIndex)
            }

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
        .opacity(isCurrent ? 1 : LiveSetlistWaveformMetrics.nonCurrentLaneOpacity)
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

    // One structure either way: branching would rebuild the lane every time the current
    // song changes, dropping its loaded waveform and its reported position.
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { event in
                        onSelect(sectionStart(atX: event.location.x))
                    },
                including: isEnabled ? .all : .subviews
            )
    }

    private func sectionStart(atX x: CGFloat) -> TimeInterval? {
        guard contentWidth > 0, duration > 0, !sections.isEmpty else { return nil }
        let time = TimelineLayout.time(at: x, duration: duration, contentWidth: contentWidth)
        let hit = sections.first { time >= $0.timelineStartSeconds && time < $0.timelineEndSeconds }
            ?? sections.last.flatMap { time >= $0.timelineStartSeconds && time <= $0.timelineEndSeconds ? $0 : nil }
        return hit?.timelineStartSeconds
    }
}
