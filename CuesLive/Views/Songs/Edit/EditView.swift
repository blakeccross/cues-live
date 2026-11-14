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
    var onBack: () -> Void = {}

    @State var activeSheet: EditSheet?
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
    @State private var showingClickEditor = false
    @State private var showingSmartGuideEditor = false
    @State var showingTempoOperations = false
    @State var trackPendingRename: AudioTrack?
    @State var renameTrackName = ""
    @State var clipSelection = ClipSelection()
    /// Shift-press on an already selected clip; removed on release unless the press became a drag.
    @State var pendingShiftDeselectID: UUID?
    @State var clipDrag: ClipDrag?
    /// The clip under the pointer, which shows its fade curve and knobs.
    @State var hoveredClipID: UUID?
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
        editorWithLifecycle
            .sheet(item: $activeSheet, onDismiss: performPendingAddTrack) { sheet in
                sheetContent(for: sheet)
            }
            .modifier(addTrackFlowModifier)
            .modifier(detectSectionsModifier)
            .alert("Rename Track", isPresented: isRenamingTrack) {
                TextField("Track name", text: $renameTrackName)
                Button("Rename", action: applyTrackRename)
                Button("Cancel", role: .cancel) {
                    trackPendingRename = nil
                }
            }
            #if os(macOS)
            .toolbar { editToolbar }
            .appLockToolbarDisplayMode()
            #endif
    }

    /// The timeline with focus, keyboard, and drop handling.
    private var focusableEditor: some View {
        editorRoot
            .background(Color.dawTimelineBackground)
            .modifier(AudioFileDropModifier(
                isTargeted: $isAudioDropTargeted,
                onDrop: performAudioFileDrop
            ))
            .focusable()
            .focused($isTimelineFocused)
            .focusEffectDisabled()
            // A setlist-following editor leaves mapped keys and MIDI with the setlist screen.
            .liveInputMappingSession(isEnabled: !viewModel.followsSetlist, takesKeyFocus: false) { action in
                handleMappedLiveAction(action)
            }
            .focusedValue(\.clipEditorActions, clipEditorActions)
            .focusedValue(\.trackHeightActions, trackHeightActions)
            .focusedValue(\.timelineZoomActions, timelineZoomActions)
            .onKeyPress(phases: .down, action: handleTrackHeightKeyPress)
            #if os(macOS)
            .onDeleteCommand(perform: removeClipSelection)
            .onCommand(#selector(NSResponder.selectAll(_:)), perform: selectAllClips)
            .onExitCommand {
                clipSelection.deselectAll()
            }
            #endif
    }

    /// Setup on appear, and the work that follows timeline, selection, and cue changes.
    private var editorWithLifecycle: some View {
        focusableEditor
            .onAppear(perform: handleAppear)
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
                if !viewModel.followsSetlist {
                    sectionPlaybackMonitors
                }
            }
            .task(id: cuedSectionID) {
                await flashCuedSection()
            }
    }

    private var isRenamingTrack: Binding<Bool> {
        Binding(
            get: { trackPendingRename != nil },
            set: { if !$0 { trackPendingRename = nil } }
        )
    }

    private func handleAppear() {
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

    /// Control-Option-Up/Down steps the selected lanes' height; Shift steps every lane.
    private func handleTrackHeightKeyPress(_ press: KeyPress) -> KeyPress.Result {
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

    /// Blinks the cued section's marker until the cue fires or is cleared.
    private func flashCuedSection() async {
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
    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        EditSongToolbarContent(
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
            onBack: viewModel.followsSetlist ? nil : onBack,
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
            registerUndo: registerSnapshotChange(_:before:after:),
            onClickTrackGenerated: reloadTimelineFromProject,
            showingClickEditor: $showingClickEditor,
            showingSmartGuideEditor: $showingSmartGuideEditor
        )
    }
    #endif

    /// Cue, Smart Guide and loop playback for an editor that owns the transport.
    @ViewBuilder
    private var sectionPlaybackMonitors: some View {
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
        midiEvents: .constant([])
    )
}
