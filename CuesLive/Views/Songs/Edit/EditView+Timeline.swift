import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditView {
    var sourceDuration: TimeInterval {
        song.sortedTracks
            .map { viewModel.fileDuration(for: $0) }
            .max() ?? finiteEngineDuration
    }

    private var finiteEngineDuration: TimeInterval {
        AudioEngineManager.shared.duration
    }

    /// Where the song ends: the last clip or section.
    var songDuration: TimeInterval {
        let duration = timeline.duration
        if duration > 0 {
            return duration
        }
        return max(sourceDuration, finiteEngineDuration, 1)
    }

    /// Length the editor lays out, including empty measures after the song's end. A video that
    /// runs past the audio extends it, so the whole clip can be seen and moved.
    var timelineDuration: TimeInterval {
        TimelineTrailingSpace.displayDuration(
            songDuration: max(songDuration, videoEndSeconds),
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
    }

    /// Before geometry is measured, `timelineZoom` is still 1 and would lay out the full
    /// natural width (~duration × 6 px). Use a fit-to-viewport estimate until then.
    private var resolvedTimelineZoom: CGFloat {
        guard timelineViewportWidth > 0 else {
            return TimelineLayout.minZoom(duration: timelineDuration, viewportWidth: 1200)
        }
        return timelineZoom
    }

    var timelineContentWidth: CGFloat {
        TimelineLayout.contentWidth(for: timelineDuration, zoom: resolvedTimelineZoom)
    }

    /// Fills the scroll viewport when song content is narrower than the editor area.
    private var timelineDisplayWidth: CGFloat {
        max(timelineContentWidth, timelineViewportWidth)
    }

    private var hasTimelineContent: Bool {
        !song.sortedTracks.isEmpty || !displaySections.isEmpty || !song.midiTracks.isEmpty
            || song.videoTrack != nil
    }

    private var timelineLoadingPlaceholder: some View {
        VStack(spacing: AppSpacing.sm) {
            Spacer(minLength: 0)
            ProgressView("Loading timeline…")
                .controlSize(.regular)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.Timeline.background)
    }

    /// Where Play begins: the range start while a selection is showing, otherwise the insertion.
    var playbackStart: TimeInterval {
        if let selection = editSelection, selection.end - selection.start > ClipEditing.tolerance {
            return selection.start
        }
        return insertionTime
    }

    /// Selector press records the insertion. Play is what moves the red playhead there.
    func placeInsertion(on trackID: UUID, at time: TimeInterval) {
        insertionTime = max(0, time)
        selectedTrackIDs = [trackID]
    }

    func playFromInsertion() {
        viewModel.seekAndPlay(to: playbackStart)
    }

    @ViewBuilder
    var editorRoot: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            EditTransportStatusStrip(viewModel: viewModel)
            editorTimeline
            if viewModel.followsSetlist {
                LiveTransportBottomBar {
                    EditFollowingSetlistStatus(isActiveSong: viewModel.isActiveSetlistSong)
                }
            }
        }
        #else
        transportChrome {
            editorTimeline
        }
        #endif
    }

    @ViewBuilder
    private var editorTimeline: some View {
        if hasTimelineContent {
            if isTimelineReady {
                dawTimeline
            } else {
                timelineLoadingPlaceholder
            }
        } else {
            emptyTracksPlaceholder
        }
    }

    private func transportChrome<Chrome: View>(@ViewBuilder content: () -> Chrome) -> some View {
        EditTransportBar(
            viewModel: viewModel,
            song: song,
            showingArrangementEditor: $showingArrangementEditor,
            arrangementActions: arrangementActions,
            loopSectionIDs: loopSectionIDs,
            isDetectingSections: isDetectingSections,
            onChangeKey: { activeSheet = .changeKey },
            onManageGroups: { activeSheet = .groupEditor },
            onDetectSections: requestDetectSections,
            onImportAbleton: presentAbletonImporter,
            onAddMIDILane: { activeSheet = .midiDevicePicker },
            onAddVideo: presentVideoImporter,
            onClearMarkerCue: { clearMarkerCue() },
            captureSnapshot: captureSnapshot,
            currentSectionAtTime: { time in
                displaySections.section(atTimeline: time)
            },
            onStopTransport: stopTransport,
            onToggleLoopAtTime: toggleLoop(at:),
            onToggleFade: toggleGroupMixFade,
            groupMixFade: groupMixFade,
            onPlay: playFromInsertion,
            stoppedDisplayTime: playbackStart,
            registerUndo: registerSnapshotChange(_:before:after:),
            onClickTrackGenerated: reloadTimelineFromProject,
            onBack: onBack,
            undoController: undoController,
            content: content()
        )
    }

    private var dawTimeline: some View {
        stemTimeline
    }

    private var stemTimeline: some View {
        EditStemTimelineView(
            timelineDuration: timelineDuration,
            timelineContentWidth: timelineContentWidth,
            timelineDisplayWidth: timelineDisplayWidth,
            sectionTimes: sectionMarkerTimes,
            laneHeights: laneFrames.rows.map(\.height),
            showsPlayhead: viewModel.isActiveSetlistSong,
            timelineViewportWidth: $timelineViewportWidth,
            isTimelineFocused: $isTimelineFocused,
            onWheelZoom: zoomTimeline(by:),
            ruler: { timelineRulerStack },
            timeRuler: { timelineTimeRuler },
            laneCanvas: trackLaneCanvas,
            lanes: { trackTimelineScrollContent },
            headerRulerCorner: { trackHeaderRulerCorner },
            timeRulerCorner: { trackHeaderTimeRulerCorner },
            headers: { trackHeaderList }
        )
        .simultaneousGesture(timelinePinchGesture)
    }

    private var timelineRulerStack: some View {
        timelineRulerSection
            .background(AppColors.Timeline.stickyRulerBackground)
            .frame(width: timelineDisplayWidth, height: TimelineLayout.topRulerHeight, alignment: .leading)
    }

    private var timelineTimeRuler: some View {
        TimelineTimeRulerView(
            duration: timelineDuration,
            contentWidth: timelineContentWidth,
            displayWidth: timelineDisplayWidth,
            height: TimelineLayout.rulerHeight
        )
        .frame(width: timelineDisplayWidth, height: TimelineLayout.rulerHeight, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var timelineRulerSection: some View {
        TimelineRulerView(
            duration: timelineDuration,
            contentWidth: timelineContentWidth,
            displayWidth: timelineDisplayWidth,
            sections: displaySections,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            loopSectionIDs: loopSectionIDs,
            sectionMarkerHeight: TimelineLayout.sectionMarkerHeight,
            timeSignatureRulerHeight: TimelineLayout.timeSignatureRulerHeight,
            tempoRulerHeight: TimelineLayout.tempoRulerHeight,
            isPlaying: audioEngine.isPlaying,
            onCueSection: cueSection,
            onToggleLoopSection: toggleLoopSection,
            onAddSection: addSection,
            onRenameSection: beginRenameSection,
            onRemoveMarker: removeMarker,
            previewSections: previewSections(_:),
            onEditSectionEdge: applySectionEdge(_:),
            onTimeSignatureRulerTap: handleTimeSignatureRulerTap,
            onEditTimeSignatureMarker: { marker in
                activeSheet = .timeSignatureChange(TimeSignatureLanePrompt(
                    measure: marker.startMeasure,
                    numerator: marker.numerator,
                    denominator: marker.denominator,
                    markerID: marker.id
                ))
            },
            onDeleteTimeSignatureMarker: deleteTimeSignatureMarker,
            onMoveTimeSignatureMarker: moveTimeSignatureMarker,
            onTempoRulerTap: handleTempoRulerTap,
            onEditTempoMarker: { marker in
                activeSheet = .tempoChange(TempoLanePrompt(
                    measure: marker.startMeasure,
                    bpm: marker.bpm,
                    markerID: marker.id
                ))
            },
            onDeleteTempoMarker: deleteTempoMarker,
            onMoveTempoMarker: moveTempoMarker,
            onTempoOperations: { showingTempoOperations = true }
        )
        .frame(height: TimelineLayout.topRulerHeight)
        .id("\(displaySections.map(\.id))|\(timelineContentWidth)|\(normalizedTempoChanges.map(\.id))|\(normalizedTimeSignatureChanges.map(\.id))")
        .popover(isPresented: $showingTempoOperations, arrowEdge: .bottom) {
            TempoOperationsMenu(
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                playhead: audioEngine.currentTime,
                onApply: applyTempoOperation
            )
        }
    }

    private var trackTimelineScrollContent: some View {
        // Transparent: the lane canvas behind it draws the background, clip bodies and waveforms.
        ZStack(alignment: .topLeading) {
            trackLanesContent
                .frame(width: timelineContentWidth, alignment: .topLeading)

            TimelineMeasureGridOverlay(
                duration: timelineDuration,
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                contentWidth: timelineContentWidth,
                displayWidth: timelineDisplayWidth,
                rulerHeight: 0,
                showsThroughContent: true,
                headerBands: clipHeaderBands
            )

            clipRangeSelectionOverlay
            insertionCursorOverlay
        }
        .frame(width: timelineDisplayWidth, height: trackAreaHeight, alignment: .topLeading)
        // On macOS the lanes live in their own AppKit scroll view, which does not pass
        // pinches up to the editor's gesture. Recognise them here as well.
        .simultaneousGesture(timelinePinchGesture)
    }

    private var trackLanesContent: some View {
        // Rows are looked up by track ID from one snapshot. The lazy stack builds rows after this
        // body runs, so an index offset read then (a video or MIDI lane just added) could point
        // past the end of these frames.
        let rowByID = laneRowsByTrackID
        return LazyVStack(spacing: TimelineLayout.laneSpacing) {
            if let video = song.videoTrack, let row = rowByID[video.id] {
                videoLane(video, height: row.height, originY: row.originY)
            }

            ForEach(midiTracks, id: \.id) { track in
                MIDILaneView(
                    track: track,
                    device: track.device,
                    timelineDuration: timelineDuration,
                    timelineContentWidth: timelineContentWidth,
                    laneHeight: rowByID[track.id]?.height ?? TrackLaneHeight.resolved(track.laneHeight),
                    events: $midiEvents,
                    tempoChanges: normalizedTempoChanges,
                    timeSignatureChanges: normalizedTimeSignatureChanges,
                    onCommit: commitMIDIEvents
                )
                .frame(width: timelineContentWidth, alignment: .leading)
            }

            ForEach(song.sortedTracks, id: \.id) { track in
                if FileStore.cachedTrackURL(for: song, track: track) != nil, let row = rowByID[track.id] {
                WaveformLaneView(
                    track: track,
                    fileDuration: viewModel.fileDuration(for: track),
                    timelineDuration: timelineDuration,
                    timelineContentWidth: timelineContentWidth,
                    clips: timeline.clips(forTrack: track.id),
                    sections: displaySections,
                    selection: clipSelection,
                    clipDrag: clipDrag,
                    hoveredClipID: hoveredClipID,
                    actions: clipLaneActions,
                    tempoChanges: normalizedTempoChanges,
                    timeSignatureChanges: normalizedTimeSignatureChanges,
                    laneHeight: row.height,
                    laneOriginY: row.originY,
                    onCueSection: cueSection,
                    loopSectionIDs: loopSectionIDs,
                    onToggleLoopSection: toggleLoopSection
                )
                .frame(width: timelineContentWidth, alignment: .leading)
                }
            }
        }
        .frame(width: timelineContentWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .coordinateSpace(name: TimelineLayout.trackLanesCoordinateSpace)
    }

    /// Full-lane wash for the edit selection, painted over the clips and the grid.
    /// It stays after the drag that created it.
    @ViewBuilder
    private var clipRangeSelectionOverlay: some View {
        if let drag = editSelection, drag.end - drag.start > ClipEditing.tolerance {
            let x0 = TimelineLayout.xPosition(
                for: drag.start,
                duration: timelineDuration,
                contentWidth: timelineContentWidth
            )
            let x1 = TimelineLayout.xPosition(
                for: drag.end,
                duration: timelineDuration,
                contentWidth: timelineContentWidth
            )
            let frames = laneFrames
            ZStack(alignment: .topLeading) {
                // The selection keeps row numbers from before a lane was added or removed.
                ForEach(selectionRows(drag, in: frames), id: \.self) { row in
                    let lane = frames.rows[row]
                    Rectangle()
                        .fill(AppColors.Timeline.selection)
                        .frame(width: max(x1 - x0, 1), height: lane.height)
                        .offset(x: x0, y: lane.originY)
                }
            }
            .frame(width: timelineContentWidth, height: trackAreaHeight, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    private var insertionRows: [Int] {
        displayedTrackIDs.enumerated().compactMap { index, id in
            selectedTrackIDs.contains(id) ? index : nil
        }
    }

    private var showsInsertionCursor: Bool {
        guard !audioEngine.isPlaying, !insertionRows.isEmpty else { return false }
        if let selection = editSelection, selection.end - selection.start > ClipEditing.tolerance {
            return false
        }
        return true
    }

    @ViewBuilder
    private var insertionCursorOverlay: some View {
        if showsInsertionCursor {
            TimelineInsertionCursor(
                time: insertionTime,
                duration: timelineDuration,
                contentWidth: timelineContentWidth,
                rows: insertionRows.compactMap { laneFrames.rows.indices.contains($0) ? laneFrames.rows[$0] : nil },
                areaHeight: trackAreaHeight
            )
        }
    }

    /// The video lane first, then MIDI, then audio, matching the header and lane order.
    var displayedTrackIDs: [UUID] {
        (song.videoTrack.map { [$0.id] } ?? []) + midiTracks.map(\.id) + song.sortedTracks.map(\.id)
    }

    /// Clips as drawn, including an in-progress move, trim or fade.
    var previewClips: [TrackClip] {
        guard let clipDrag else { return timeline.clips }
        let durations = Dictionary(uniqueKeysWithValues: song.sortedTracks.map { ($0.id, viewModel.fileDuration(for: $0)) })
        return clipDrag.applied(
            to: timeline.clips,
            clipIDs: clipSelection.clipIDs,
            sourceDuration: { durations[$0] ?? 0 }
        )
    }

    /// Name bars of the clips on screen. Measure lines stop here so the header stays opaque.
    private var clipHeaderBands: [CGRect] {
        let ids = displayedTrackIDs
        guard !ids.isEmpty else { return [] }
        let frames = laneFrames
        let rowOf = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return previewClips.compactMap { clip in
            guard let row = rowOf[clip.trackID] else { return nil }
            let x0 = TimelineLayout.xPosition(
                for: clip.timelineStartSeconds,
                duration: timelineDuration,
                contentWidth: timelineContentWidth
            )
            let x1 = TimelineLayout.xPosition(
                for: clip.timelineEndSeconds,
                duration: timelineDuration,
                contentWidth: timelineContentWidth
            )
            let width = x1 - x0
            guard width > 0 else { return nil }
            return CGRect(
                x: x0,
                y: frames.rows[row].originY,
                width: width,
                height: TimelineLayout.clipHeaderHeight
            )
        }
    }

    private var trackHeaderList: some View {
        LazyVStack(spacing: TimelineLayout.laneSpacing) {
            if let video = song.videoTrack {
                videoTrackHeader(video)
            }

            ForEach(midiTracks, id: \.id) { track in
                MIDITrackHeaderView(
                    track: track,
                    laneHeight: TrackLaneHeight.resolved(track.laneHeight),
                    isSelected: selectedTrackIDs.contains(track.id),
                    onSelect: { modifiers in
                        selectedTrackIDs = TrackSelection.click(
                            id: track.id,
                            in: selectedTrackIDs,
                            order: displayedTrackIDs,
                            modifiers: modifiers
                        )
                    },
                    onConfigChange: commitMIDIConfig,
                    onSendTest: { sendMIDITest(for: track) },
                    onEditDevice: { editDevice(for: track) },
                    onDelete: { deleteMIDITrack(track) },
                    onResize: { resizeLane(track.id, by: $0) },
                    onResizeEnded: finishLaneResize
                )
            }

            ForEach(song.sortedTracks, id: \.id) { track in
                TrackLaneHeaderView(
                    track: track,
                    laneHeight: TrackLaneHeight.resolved(track.laneHeight),
                    isSelected: selectedTrackIDs.contains(track.id),
                    groups: trackGroups,
                    onSelect: { modifiers in
                        selectedTrackIDs = TrackSelection.click(
                            id: track.id,
                            in: selectedTrackIDs,
                            order: displayedTrackIDs,
                            modifiers: modifiers
                        )
                    },
                    onMixChange: {
                        performUndoableChange("Mix Track") {
                            viewModel.updateMix(for: track, context: modelContext)
                        }
                    },
                    onGroupChange: {
                        performUndoableChange("Assign Group") {
                            viewModel.updateGroup(for: track, context: modelContext)
                        }
                    },
                    onManageGroups: {
                        activeSheet = .groupEditor
                    },
                    onRename: {
                        beginRenameTrack(track)
                    },
                    onDelete: {
                        deleteAudioTrack(track)
                    },
                    onResize: { resizeLane(track.id, by: $0) },
                    onResizeEnded: finishLaneResize
                )
            }
        }
        .frame(width: TimelineLayout.trackHeaderWidth)
        .background(AppColors.Timeline.trackHeaderColumnBackground)
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            guard audioEngine.isPlaying || audioEngine.hasVisibleMeterLevel else { return }
            audioEngine.refreshGroupMeters()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.Timeline.divider)
                .frame(width: 1)
        }
    }

    private func rulerLaneLabel(_ title: String, height: CGFloat) -> some View {
        Text(title)
            .font(AppTypography.Compact.label)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, AppSpacing.xs)
            .frame(height: height)
    }

    private var rulerLaneDivider: some View {
        Rectangle()
            .fill(AppColors.Timeline.divider)
            .frame(height: 1)
            .allowsHitTesting(false)
    }

    private var trackHeaderRulerCorner: some View {
        VStack(spacing: 0) {
            rulerLaneLabel("Meter", height: TimelineLayout.timeSignatureRulerHeight)
            rulerLaneLabel("Tempo", height: TimelineLayout.tempoRulerHeight)
            rulerLaneLabel("Markers", height: TimelineLayout.sectionMarkerHeight)
        }
        .frame(width: TimelineLayout.trackHeaderWidth, height: TimelineLayout.topRulerHeight)
        .background(AppColors.Timeline.trackHeaderBackground)
        .overlay(alignment: .bottom) { rulerLaneDivider }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.Timeline.divider)
                .frame(width: 1)
        }
    }

    private var trackHeaderTimeRulerCorner: some View {
        Rectangle()
            .fill(AppColors.Timeline.stickyRulerBackground)
            .frame(width: TimelineLayout.trackHeaderWidth, height: TimelineLayout.rulerHeight)
            .allowsHitTesting(false)
    }
}
