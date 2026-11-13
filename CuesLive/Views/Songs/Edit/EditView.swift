import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct TempoLanePrompt: Identifiable {
    let id = UUID()
    let measure: Int
    let bpm: Double
    let markerID: UUID?
}

struct TimeSignatureLanePrompt: Identifiable {
    let id = UUID()
    let measure: Int
    let numerator: Int
    let denominator: Int
    let markerID: UUID?
}

struct LaneResizeDrag {
    var trackID: UUID
    var startHeight: CGFloat
    var before: SongEditSnapshot
}

struct ClipGainPromptRequest: Identifiable {
    let id = UUID()
    /// Shared gain when every selected clip matches. Empty when the selection is mixed.
    let decibels: Double?
    let clipCount: Int
}

struct EditView: View {
    @Environment(\.modelContext) var modelContext

    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    let undoController: SongUndoController
    @Binding var timeline: SongTimeline
    @Binding var tempoChanges: [TempoChange]
    @Binding var timeSignatureChanges: [TimeSignatureChange]
    @Binding var midiEvents: [MIDIEvent]
    @Binding var showingSongLibrary: Bool
    var onBack: () -> Void = {}

    @State var showingMIDIDevicePicker = false
    @State var deviceBeingEdited: MIDIDevice?
    @State var showingAddTrackOptions = false
    @State var pendingAddTrackKind: AddTrackKind?
    @State var showingTrackImporter = false
    @State var showingAbletonImporter = false
    @State var importError: String?
    @State var isDetectingSections = false
    @State var sectionDetectionError: String?
    @State var showingDetectSectionsConfirm = false
    @State var abletonImportSummary: String?
    @State var timelineZoom: CGFloat = 1
    @State var timelineViewportWidth: CGFloat = 0
    @State var hasSetInitialTimelineZoom = false
    @State var pinchStartZoom: CGFloat?
    @State var cuedSectionID: UUID?
    @State var cueFireTime: TimeInterval?
    @State var cueFlashPhase = false
    @State var sectionLoop = SectionLoopController()
    @State var sectionAnnouncer = SectionAnnouncer()
    @State var groupMixFade = GroupMixFadeController()
    @Bindable var audioEngine = AudioEngineManager.shared
    @State var showingArrangementEditor = false
    @State var showingGroupEditor = false
    @State var showingChangeKey = false
    @State private var showingClickEditor = false
    @State private var showingSmartGuideEditor = false
    @State var showingTempoOperations = false
    @State var tempoLanePrompt: TempoLanePrompt?
    @State var timeSignatureLanePrompt: TimeSignatureLanePrompt?
    @State var sectionPendingRename: SongSection?
    @State var sectionNamePromptTitle = "Rename Section"
    @State var trackPendingRename: AudioTrack?
    @State var renameTrackName = ""
    @State var clipSelection = ClipSelection()
    /// Shift-press on an already selected clip; removed on release unless the press became a drag.
    @State var pendingShiftDeselectID: UUID?
    @State var clipDrag: ClipDrag?
    @State var gainPrompt: ClipGainPromptRequest?
    /// The edit selection. A selector drag writes it, and it stays after the pointer
    /// goes up. A click replaces it with an insertion, which has no range.
    @State var editSelection: ClipRangeDrag?
    @State var selectedTrackIDs: Set<UUID> = []
    /// Bottom-edge drag. The snapshot is the height before the pointer moved.
    @State var laneResize: LaneResizeDrag?
    /// Snapped lane position Play starts from. A click places it; playback does not move it.
    @State var insertionTime: TimeInterval = 0
    @FocusState var isTimelineFocused: Bool
    @State var isTimelineReady = false
    @State var isAudioDropTargeted = false

    @Query(sort: [SortDescriptor(\TrackGroup.sortOrder), SortDescriptor(\TrackGroup.name)])
    var trackGroups: [TrackGroup]

    var body: some View {
        editorRoot
        .background(Color.dawTimelineBackground)
        .modifier(AudioFileDropModifier(
            isTargeted: $isAudioDropTargeted,
            onDrop: performAudioFileDrop
        ))
        .focusable()
        .focused($isTimelineFocused)
        .focusEffectDisabled()
        .liveInputMappingSession(takesKeyFocus: false) { action in
            handleMappedLiveAction(action)
        }
        .focusedValue(\.clipEditorActions, clipEditorActions)
        .focusedValue(\.trackHeightActions, trackHeightActions)
        .onKeyPress(phases: .down) { press in
            guard isTimelineFocused else { return .ignored }
            guard press.modifiers.contains(.control),
                  press.modifiers.contains(.option),
                  !press.modifiers.contains(.command),
                  press.key == .upArrow || press.key == .downArrow
            else { return .ignored }
            stepTrackHeight(
                taller: press.key == .upArrow,
                option: true,
                shift: press.modifiers.contains(.shift)
            )
            return .handled
        }
        .onAppear {
            isTimelineFocused = true
            tempoChanges = normalizedTempoChanges
            timeSignatureChanges = normalizedTimeSignatureChanges
            viewModel.syncTempoMap(tempoChanges, timeSignatureChanges: timeSignatureChanges)
            reconfigureMIDI()
            prepareSectionAnnouncements()
            Task { @MainActor in
                await Task.yield()
                isTimelineReady = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .outputRoutingDidChange)) { _ in
            viewModel.applyOutputRoutingChange()
        }
        .onChange(of: clipSelection) { _, newValue in
            if !newValue.isEmpty {
                isTimelineFocused = true
            }
        }
        .onChange(of: timeline.markers) { _, _ in
            prepareSectionAnnouncements()
        }
        .onChange(of: song.smartGuideEnabled) { _, _ in
            prepareSectionAnnouncements()
        }
        .onChange(of: timelineDuration) { _, _ in
            clampTimelineZoom()
        }
        .onChange(of: timelineViewportWidth) { _, _ in
            clampTimelineZoom()
        }
        .background {
            SectionCueMonitor(
                cuedSectionID: cuedSectionID,
                cueFireTime: cueFireTime,
                onFire: fireMarkerCue
            )
            SectionAnnounceMonitor(
                enabled: song.smartGuideEnabled,
                sections: displaySections,
                cuedSectionID: cuedSectionID,
                cueFireTime: cueFireTime,
                loopSection: sectionLoop.activeSection(in: displaySections, loopSectionIDs: loopSectionIDs),
                announcer: sectionAnnouncer
            )
            SectionLoopPlaybackSupport(
                loopController: sectionLoop,
                sections: displaySections,
                loopSectionIDs: loopSectionIDs,
                onLoopActivated: { clearMarkerCue() }
            )
        }
        .task(id: cuedSectionID) {
            guard cuedSectionID != nil else {
                cueFlashPhase = false
                return
            }
            cueFlashPhase = true
            while !Task.isCancelled, cuedSectionID != nil {
                try? await Task.sleep(for: .milliseconds(350))
                cueFlashPhase.toggle()
            }
        }
#if os(macOS)
        .onDeleteCommand {
            removeClipSelection()
        }
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            selectAllClips()
        }
        .onExitCommand {
            clipSelection.deselectAll()
        }
#endif
        .sheet(isPresented: $showingGroupEditor) {
            TrackGroupEditorView()
        }
        .sheet(isPresented: $showingChangeKey) {
            ChangeKeyDialog(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: { actionName, before, after in
                    undoController.registerChange(
                        actionName: actionName,
                        before: before,
                        after: after,
                        apply: { snapshot in
                            applySnapshot(snapshot)
                        }
                    )
                }
            )
        }
        .sheet(isPresented: $showingMIDIDevicePicker) {
            MIDIDevicePickerView { device in
                createMIDITrack(for: device)
            }
        }
        .sheet(item: $deviceBeingEdited) { device in
            NavigationStack {
                MIDIDeviceEditorView(device: device) { _ in
                    commitMIDIConfig()
                }
            }
            // `.sheet(item:)` alone can still let the NavigationStack-wrapped
            // content reuse its previous `@State` (destination, channel,
            // commands) instead of reinitializing from `device`, since the
            // NavigationStack's own identity sits between the sheet and the
            // editor. Keying explicitly by `device.id` forces a genuinely new
            // view — and fresh `@State` — every time a different device (or
            // the same one, after a prior edit) is opened.
            .id(device.id)
            .formSheetFrame(minWidth: 420, minHeight: 460)
        }
        .sheet(isPresented: $showingAddTrackOptions, onDismiss: performPendingAddTrack) {
            AddTrackTypeSheet { kind in
                pendingAddTrackKind = kind
                showingAddTrackOptions = false
            }
        }
        .modifier(addTrackFlowModifier)
        .sheet(item: $sectionPendingRename) { section in
            RenameSectionSheet(title: sectionNamePromptTitle, currentName: section.name) { newName in
                applySectionRename(newName)
            }
        }
        .sheet(item: $tempoLanePrompt) { prompt in
            TempoChangePrompt(
                measure: prompt.measure,
                currentBPM: prompt.bpm,
                tracks: song.sortedTracks,
                onCancel: { tempoLanePrompt = nil },
                onChange: { bpm, lockedTrackIDs in
                    applyTempoChange(prompt: prompt, bpm: bpm, lockedTrackIDs: lockedTrackIDs)
                }
            )
        }
        .sheet(item: $timeSignatureLanePrompt) { prompt in
            TimeSignatureChangePrompt(
                measure: prompt.measure,
                numerator: prompt.numerator,
                denominator: prompt.denominator,
                onCancel: { timeSignatureLanePrompt = nil },
                onChange: { numerator, denominator in
                    applyTimeSignatureChange(
                        prompt: prompt,
                        numerator: numerator,
                        denominator: denominator
                    )
                }
            )
        }
        .modifier(detectSectionsModifier)
        .alert("Rename Track", isPresented: Binding(
            get: { trackPendingRename != nil },
            set: { if !$0 { trackPendingRename = nil } }
        )) {
            TextField("Track name", text: $renameTrackName)
            Button("Rename") {
                applyTrackRename()
            }
            Button("Cancel", role: .cancel) {
                trackPendingRename = nil
            }
        }
        .sheet(item: $gainPrompt) { prompt in
            ClipGainPrompt(
                initialDecibels: prompt.decibels,
                clipCount: prompt.clipCount,
                onCancel: { gainPrompt = nil },
                onApply: applyClipGain
            )
        }
#if os(macOS)
        .toolbar {
            EditSongToolbarContent(
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
                onBack: onBack,
                currentSectionAtTime: { time in
                    displaySections.section(atTimeline: time)
                },
                onStopTransport: stopTransport,
                onToggleLoopAtTime: toggleLoop(at:),
                onToggleFade: toggleGroupMixFade,
                groupMixFade: groupMixFade,
                onPlay: playFromInsertion,
                stoppedDisplayTime: playbackStart,
                captureSnapshot: captureSnapshot,
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
                showingClickEditor: $showingClickEditor,
                showingSmartGuideEditor: $showingSmartGuideEditor
            )
        }
        .appLockToolbarDisplayMode()
#endif
    }

    /// A selector drag: a snapped time range across every row from the press to the pointer.
    struct ClipRangeDrag: Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var firstRow: Int
        var lastRow: Int
    }
}
#Preview {
    EditView(
        song: Song(name: "Preview"),
        viewModel: SongEditorViewModel(song: Song(name: "Preview")),
        undoController: SongUndoController(),
        timeline: .constant(SongTimeline()),
        tempoChanges: .constant([TempoChange(startMeasure: 1, bpm: 120)]),
        timeSignatureChanges: .constant([
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0)
        ]),
        midiEvents: .constant([]),
        showingSongLibrary: .constant(false)
    )
}
