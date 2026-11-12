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

    var timelineDuration: TimeInterval {
        let duration = timeline.duration
        if duration > 0 {
            return duration
        }
        return max(sourceDuration, finiteEngineDuration, 1)
    }

    private var timelineMinZoom: CGFloat {
        TimelineLayout.minZoom(duration: timelineDuration, viewportWidth: timelineViewportWidth)
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
    }

    private var timelineLoadingPlaceholder: some View {
        VStack(spacing: AppSpacing.sm) {
            Spacer(minLength: 0)
            ProgressView("Loading timeline…")
                .controlSize(.regular)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dawTimelineBackground)
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

    func clampTimelineZoom() {
        guard timelineViewportWidth > 0 else { return }
        let minZoom = timelineMinZoom
        if !hasSetInitialTimelineZoom {
            timelineZoom = minZoom
            hasSetInitialTimelineZoom = true
        } else {
            timelineZoom = min(TimelineLayout.maxZoom, max(minZoom, timelineZoom))
        }
    }

    #if os(macOS)
    private var editorTransportCluster: some View {
        EditSongTransportCluster(
            viewModel: viewModel,
            loopSectionIDs: loopSectionIDs,
            currentSectionAtTime: { time in
                displaySections.section(atTimeline: time)
            },
            onStopTransport: {
                clearMarkerCue()
                viewModel.stop()
            },
            onToggleLoopAtTime: { time in
                guard let section = displaySections.section(atTimeline: time) else { return }
                toggleLoopSection(section)
            },
            onPlay: playFromInsertion,
            stoppedDisplayTime: playbackStart
        )
    }
    #endif

    @ViewBuilder
    var editorRoot: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            EditTransportStatusStrip(viewModel: viewModel)
            editorTimeline
            if LiveTransportLayout.macOSPlacesControlsAtBottom {
                LiveTransportBottomBar {
                    editorTransportCluster
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
            showingChangeKey: $showingChangeKey,
            arrangementActions: arrangementActions,
            loopSectionIDs: loopSectionIDs,
            showingSongLibrary: $showingSongLibrary,
            showingGroupEditor: $showingGroupEditor,
            isDetectingSections: isDetectingSections,
            onDetectSections: requestDetectSections,
            onImportAbleton: presentAbletonImporter,
            onAddMIDILane: { showingMIDIDevicePicker = true },
            onClearMarkerCue: { clearMarkerCue() },
            captureSnapshot: captureSnapshot,
            currentSectionAtTime: { time in
                displaySections.section(atTimeline: time)
            },
            onStopTransport: {
                clearMarkerCue()
                viewModel.stop()
            },
            onToggleLoopAtTime: { time in
                guard let section = displaySections.section(atTimeline: time) else { return }
                toggleLoopSection(section)
            },
            onPlay: playFromInsertion,
            stoppedDisplayTime: playbackStart,
            registerUndo: { actionName, before, after in
                undoController.registerChange(
                    actionName: actionName,
                    before: before,
                    after: after,
                    apply: { snapshot in
                        applySnapshot(snapshot)
                    }
                )
            },
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
            timelineViewportWidth: $timelineViewportWidth,
            isTimelineFocused: $isTimelineFocused,
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
            .background(Color.dawStickyRulerBackground)
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
            onTimeSignatureRulerTap: handleTimeSignatureRulerTap,
            onEditTimeSignatureMarker: { marker in
                timeSignatureLanePrompt = TimeSignatureLanePrompt(
                    measure: marker.startMeasure,
                    numerator: marker.numerator,
                    denominator: marker.denominator,
                    markerID: marker.id
                )
            },
            onDeleteTimeSignatureMarker: deleteTimeSignatureMarker,
            onMoveTimeSignatureMarker: moveTimeSignatureMarker,
            onTempoRulerTap: handleTempoRulerTap,
            onEditTempoMarker: { marker in
                tempoLanePrompt = TempoLanePrompt(
                    measure: marker.startMeasure,
                    bpm: marker.bpm,
                    markerID: marker.id
                )
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
        let frames = laneFrames
        return LazyVStack(spacing: TimelineLayout.laneSpacing) {
            ForEach(Array(midiTracks.enumerated()), id: \.element.id) { index, track in
                MIDILaneView(
                    track: track,
                    device: track.device,
                    timelineDuration: timelineDuration,
                    timelineContentWidth: timelineContentWidth,
                    laneHeight: frames.rows[index].height,
                    events: $midiEvents,
                    tempoChanges: normalizedTempoChanges,
                    timeSignatureChanges: normalizedTimeSignatureChanges,
                    onCommit: commitMIDIEvents
                )
                .frame(width: timelineContentWidth, alignment: .leading)
            }

            ForEach(Array(song.sortedTracks.enumerated()), id: \.element.id) { index, track in
                if FileStore.trackURL(for: song, track: track) != nil {
                let row = frames.rows[midiTracks.count + index]
                WaveformLaneView(
                    track: track,
                    fileDuration: viewModel.fileDuration(for: track),
                    timelineDuration: timelineDuration,
                    timelineContentWidth: timelineContentWidth,
                    clips: timeline.clips(forTrack: track.id),
                    sections: displaySections,
                    selection: clipSelection,
                    clipDrag: clipDrag,
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
                ForEach(drag.firstRow...drag.lastRow, id: \.self) { row in
                    let lane = frames.rows[row]
                    Rectangle()
                        .fill(Color.soundcraftSelection)
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

    /// MIDI lanes first, then audio, matching the header and lane order.
    var displayedTrackIDs: [UUID] {
        midiTracks.map(\.id) + song.sortedTracks.map(\.id)
    }

    /// Clips as drawn, including an in-progress move or trim.
    var previewClips: [TrackClip] {
        var preview = timeline.clips
        guard let clipDrag else { return preview }
        let ids = clipSelection.clipIDs
        guard !ids.isEmpty else { return preview }
        switch clipDrag {
        case .move(let delta, let copy):
            if copy {
                ClipEditing.copy(clipIDs: ids, by: delta, in: &preview)
            } else {
                ClipEditing.move(clipIDs: ids, by: delta, in: &preview)
            }
        case .trim(let edge, let delta):
            let durations = Dictionary(uniqueKeysWithValues: song.sortedTracks.map { ($0.id, viewModel.fileDuration(for: $0)) })
            ClipEditing.trim(
                clipIDs: ids,
                edge: edge,
                by: delta,
                sourceDuration: { durations[$0] ?? 0 },
                in: &preview
            )
        }
        return preview
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
                        showingGroupEditor = true
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
        .background(Color.dawTrackHeaderColumnBackground)
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            guard audioEngine.isPlaying || audioEngine.hasVisibleMeterLevel else { return }
            audioEngine.refreshGroupMeters()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.dawTimelineDivider)
                .frame(width: 1)
        }
    }

    private func rulerLaneLabel(_ title: String, height: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
            .frame(height: height)
    }

    private var rulerLaneDivider: some View {
        Rectangle()
            .fill(Color.dawTimelineDivider)
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
        .background(Color.dawTrackHeaderBackground)
        .overlay(alignment: .bottom) { rulerLaneDivider }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.dawTimelineDivider)
                .frame(width: 1)
        }
    }

    private var trackHeaderTimeRulerCorner: some View {
        Rectangle()
            .fill(Color.dawStickyRulerBackground)
            .frame(width: TimelineLayout.trackHeaderWidth, height: TimelineLayout.rulerHeight)
            .allowsHitTesting(false)
    }

    private var timelinePinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStartZoom == nil {
                    pinchStartZoom = timelineZoom
                }
                guard let pinchStartZoom else { return }
                let next = pinchStartZoom * scale
                timelineZoom = min(TimelineLayout.maxZoom, max(timelineMinZoom, next))
            }
            .onEnded { _ in
                pinchStartZoom = nil
            }
    }
}
