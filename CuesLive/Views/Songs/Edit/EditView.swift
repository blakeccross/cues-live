import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif


private struct TempoLanePrompt: Identifiable {
    let id = UUID()
    let measure: Int
    let bpm: Double
    let markerID: UUID?
}

struct EditView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    let undoController: SongUndoController
    @Binding var timeline: SongTimeline
    @Binding var tempoChanges: [TempoChange]
    @Binding var timeSignatureChanges: [TimeSignatureChange]
    @Binding var midiEvents: [MIDIEvent]
    @Binding var showingSongLibrary: Bool
    var onBack: () -> Void = {}

    @State private var showingMIDIDevicePicker = false
    @State private var deviceBeingEdited: MIDIDevice?
    @State private var showingAddTrackOptions = false
    @State private var pendingAddTrackKind: AddTrackKind?
    @State private var showingTrackImporter = false
    @State private var showingAbletonImporter = false
    @State private var importError: String?
    @State private var isDetectingSections = false
    @State private var sectionDetectionError: String?
    @State private var showingDetectSectionsConfirm = false
    @State private var abletonImportSummary: String?
    @State private var timelineZoom: CGFloat = 1
    @State private var timelineViewportWidth: CGFloat = 0
    @State private var hasSetInitialTimelineZoom = false
    @State private var pinchStartZoom: CGFloat?
    @State private var cuedSectionID: UUID?
    @State private var cueFireTime: TimeInterval?
    @State private var cueFlashPhase = false
    @State private var sectionLoop = SectionLoopController()
    @State private var sectionAnnouncer = SectionAnnouncer()
    @Bindable private var audioEngine = AudioEngineManager.shared
    @State private var showingArrangementEditor = false
    @State private var showingTimeSignatureEditor = false
    @State private var showingGroupEditor = false
    @State private var showingChangeKey = false
    @State private var showingTempoOperations = false
    @State private var tempoLanePrompt: TempoLanePrompt?
    @State private var showingTimeSignatureMarkerEditor = false
    @State private var editingTimeSignatureMarkerID: UUID?
    @State private var sectionPendingRename: SongSection?
    @State private var sectionNamePromptTitle = "Rename Section"
    @State private var trackPendingRename: AudioTrack?
    @State private var renameTrackName = ""
    @State private var clipSelection = ClipSelection()
    /// Shift-press on an already selected clip; removed on release unless the press became a drag.
    @State private var pendingShiftDeselectID: UUID?
    @State private var clipDrag: ClipDrag?
    /// Soundcraft's edit selection. A selector drag writes it, and it stays after the pointer
    /// goes up. A click replaces it with an insertion, which has no range.
    @State private var editSelection: ClipRangeDrag?
    @State private var selectedTrackIDs: Set<UUID> = []
    /// Snapped lane position Play starts from. A click places it; playback does not move it.
    @State private var insertionTime: TimeInterval = 0
    @FocusState private var isTimelineFocused: Bool
    @State private var isTimelineReady = false

    @Query(sort: [SortDescriptor(\TrackGroup.sortOrder), SortDescriptor(\TrackGroup.name)])
    private var trackGroups: [TrackGroup]

    private var measureNumerator: Int {
        normalizedTimeSignatureChanges.referenceNumerator
    }

    private var measureDenominator: Int {
        normalizedTimeSignatureChanges.referenceDenominator
    }

    private var normalizedTimeSignatureChanges: [TimeSignatureChange] {
        timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator,
            defaultDenominator: song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
        )
    }

    private var normalizedTempoChanges: [TempoChange] {
        tempoChanges.normalizedEnsuringInitialMarker(defaultBPM: song.bpm ?? TempoChange.defaultBPM)
    }

    private func persistTempoChanges() {
        let normalized = normalizedTempoChanges
        tempoChanges = normalized
        if song.bpm != normalized.referenceBPM {
            song.bpm = normalized.referenceBPM
            try? modelContext.save()
        }
        persistProjectState()
        viewModel.syncTempoMap(normalized, timeSignatureChanges: normalizedTimeSignatureChanges)
    }

    private func applyReferenceTempo(_ bpm: Double) {
        guard TempoChange.validBPMRange.contains(bpm) else { return }

        let current = normalizedTempoChanges.referenceBPM
        if abs(current - bpm) < 0.0001, abs((song.bpm ?? current) - bpm) < 0.0001 {
            return
        }

        performUndoableChange("Edit Tempo") {
            song.bpm = bpm
            if let index = tempoChanges.firstIndex(where: \.isOrigin) {
                let existing = tempoChanges[index]
                tempoChanges[index] = TempoChange(
                    id: existing.id,
                    startMeasure: 1,
                    beatOffset: existing.beatOffset,
                    bpm: bpm,
                    sortOrder: existing.sortOrder
                )
            } else {
                tempoChanges.insert(TempoChange(startMeasure: 1, bpm: bpm, sortOrder: 0), at: 0)
            }
            persistTempoChanges()
        }
    }

    private func applyBaseKey(_ keyRaw: String?) {
        guard song.baseKeyRaw != keyRaw else { return }
        performUndoableChange("Edit Key") {
            song.baseKeyRaw = keyRaw
            try? modelContext.save()
            persistProjectState()
        }
    }

    private func persistTimeSignatureChanges() {
        let normalized = normalizedTimeSignatureChanges
        timeSignatureChanges = normalized
        if song.timeSignatureNumerator != normalized.referenceNumerator {
            song.timeSignatureNumerator = normalized.referenceNumerator
            try? modelContext.save()
        }
        if song.timeSignatureDenominator != normalized.referenceDenominator {
            song.timeSignatureDenominator = normalized.referenceDenominator
            try? modelContext.save()
        }
        persistProjectState()
        viewModel.syncTempoMap(normalizedTempoChanges, timeSignatureChanges: normalized)
    }

    private func persistProjectState() {
        try? SongProjectBridge.persist(
            song: song,
            timeline: timeline,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            midiEvents: midiEvents,
            context: modelContext
        )
    }

    private func captureSnapshot() -> SongEditSnapshot {
        SongEditSnapshot.capture(
            song: song,
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents
        )
    }

    private func applySnapshot(_ snapshot: SongEditSnapshot) {
        timeline = snapshot.timeline
        clipSelection.retain(existing: timeline.clips)
        midiEvents = snapshot.midiEvents

        let pitchBeforeApply = pitchPlaybackSignature
        snapshot.applyMetadata(to: song)
        let trackIDsBeforeApply = Set(song.sortedTracks.map(\.id))
        snapshot.applyTracks(to: song, context: modelContext)
        let trackIDsChanged = trackIDsBeforeApply != Set(song.sortedTracks.map(\.id))
        let pitchChanged = pitchBeforeApply != pitchPlaybackSignature

        let defaultBPM = song.bpm ?? TempoChange.defaultBPM
        let defaultNumerator = song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator
        let defaultDenominator = song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
        let normalizedTempo = snapshot.normalizedTempoChanges(defaultBPM: defaultBPM)
        let normalizedTimeSignature = snapshot.normalizedTimeSignatureChanges(
            defaultNumerator: defaultNumerator,
            defaultDenominator: defaultDenominator
        )
        tempoChanges = normalizedTempo
        timeSignatureChanges = normalizedTimeSignature

        try? SongProjectBridge.persist(
            song: song,
            timeline: timeline,
            tempoChanges: normalizedTempo,
            timeSignatureChanges: normalizedTimeSignature,
            midiEvents: midiEvents,
            context: modelContext
        )
        try? modelContext.save()

        syncPlayback()
        viewModel.syncTempoMap(normalizedTempo, timeSignatureChanges: normalizedTimeSignature)

        for track in song.sortedTracks {
            viewModel.updateMix(for: track, context: modelContext)
        }

        reconfigureMIDI()

        if trackIDsChanged || pitchChanged {
            viewModel.loadSong(context: modelContext)
        }
    }

    private var pitchPlaybackSignature: String {
        let tracks = song.sortedTracks
            .map { "\($0.id.uuidString):\($0.includeInKeyChange)" }
            .joined(separator: ",")
        return "\(song.transposeSemitones)|\(tracks)"
    }

    private func performUndoableChange(_ actionName: String, _ change: () -> Void) {
        guard !undoController.isApplyingUndo else {
            change()
            return
        }
        let before = captureSnapshot()
        change()
        let after = captureSnapshot()
        undoController.registerChange(
            actionName: actionName,
            before: before,
            after: after,
            apply: { snapshot in
                applySnapshot(snapshot)
            }
        )
    }

    private func handleTempoRulerTap(at time: TimeInterval) {
        let boundary = MeasureTiming.nearestMeasureBoundary(
            to: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let existing = normalizedTempoChanges.first {
            $0.startMeasure == boundary.measure && $0.isDownbeat
        }
        let bpm = existing?.bpm ?? MeasureTiming.activeBPM(
            at: boundary.time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        tempoLanePrompt = TempoLanePrompt(
            measure: boundary.measure,
            bpm: bpm,
            markerID: existing?.id
        )
    }

    private func deleteTempoMarker(_ marker: TempoChange) {
        guard !marker.isOrigin else { return }
        performUndoableChange("Delete Tempo Marker") {
            tempoChanges.removeAll { $0.id == marker.id }
            tempoChanges = normalizedTempoChanges
            persistTempoChanges()
        }
    }

    private func handleTimeSignatureRulerTap(at time: TimeInterval) {
        let boundary = MeasureTiming.nearestMeasureBoundary(
            to: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )

        if let existing = normalizedTimeSignatureChanges.first(where: { $0.startMeasure == boundary.measure }) {
            editingTimeSignatureMarkerID = existing.id
        } else {
            let activeSignature = normalizedTimeSignatureChanges.active(atMeasure: boundary.measure)
                ?? normalizedTimeSignatureChanges.first!
            let newMarker = TimeSignatureChange(
                numerator: activeSignature.numerator,
                denominator: activeSignature.denominator,
                startMeasure: boundary.measure
            )
            timeSignatureChanges = (normalizedTimeSignatureChanges + [newMarker]).normalizedEnsuringInitialMarker(
                defaultNumerator: measureNumerator,
                defaultDenominator: measureDenominator
            )
            editingTimeSignatureMarkerID = timeSignatureChanges.first(where: { $0.startMeasure == boundary.measure })?.id
        }
        showingTimeSignatureMarkerEditor = true
    }

    private func deleteTimeSignatureMarker(_ marker: TimeSignatureChange) {
        guard marker.startMeasure > 1 else { return }
        performUndoableChange("Delete Time Signature Marker") {
            timeSignatureChanges.removeAll { $0.id == marker.id }
            timeSignatureChanges = normalizedTimeSignatureChanges
            persistTimeSignatureChanges()
        }
    }

    private var markers: [ArrangementMarker] {
        timeline.sortedMarkers
    }

    private var sourceDuration: TimeInterval {
        song.sortedTracks
            .map { viewModel.fileDuration(for: $0) }
            .max() ?? finiteEngineDuration
    }

    private var finiteEngineDuration: TimeInterval {
        AudioEngineManager.shared.duration
    }

    private var displaySections: [SongSection] {
        timeline.sections(songEnd: timeline.duration)
    }

    /// Start of each section marker, in timeline seconds.
    private var sectionMarkerTimes: [TimeInterval] {
        displaySections.map(\.timelineStartSeconds)
    }

    private var loopSectionIDs: Set<UUID> {
        Set(timeline.markers.filter(\.loops).map(\.id))
    }

    /// Picks up timeline changes written straight to the project file, such as a regenerated click clip.
    private func reloadTimelineFromProject() {
        guard let state = try? SongProjectBridge.loadProjectState(for: song) else { return }
        timeline = state.timeline
        syncPlayback()
    }

    private func syncPlayback() {
        viewModel.syncArrangement(timeline)
    }

    /// Applies one timeline edit as a single undo step, then saves and updates playback.
    private func commitTimelineEdit(_ actionName: String, _ edit: (inout SongTimeline) -> Void) {
        performUndoableChange(actionName) {
            edit(&timeline)
            persistProjectState()
            syncPlayback()
            prepareSectionAnnouncements()
        }
    }

    private var clipEditorActions: ClipEditorActions {
        ClipEditorActions(
            canSplit: !clipSelection.isEmpty,
            canJoin: !clipSelection.isEmpty,
            canDuplicate: !clipSelection.isEmpty,
            canDeselect: !clipSelection.isEmpty,
            split: { splitSelectedClips(at: AudioEngineManager.shared.currentTime) },
            join: { joinSelectedClips() },
            duplicate: { duplicateSelectedClips() },
            deselectAll: { clipSelection.deselectAll() }
        )
    }

    private var timelineDuration: TimeInterval {
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

    private var timelineContentWidth: CGFloat {
        TimelineLayout.contentWidth(for: timelineDuration, zoom: resolvedTimelineZoom)
    }

    /// Fills the scroll viewport when song content is narrower than the editor area.
    private var timelineDisplayWidth: CGFloat {
        max(timelineContentWidth, timelineViewportWidth)
    }

    private var hasTimelineContent: Bool {
        !song.sortedTracks.isEmpty || !displaySections.isEmpty || !song.midiTracks.isEmpty
    }

    private var midiTracks: [MIDITrack] {
        song.sortedMIDITracks
    }

    private func reconfigureMIDI() {
        let resolved = MIDIScheduler.scheduledEvents(events: midiEvents, tracks: midiTracks)
        AudioEngineManager.shared.configureMIDI(events: resolved)
    }

    private func commitMIDIEvents() {
        performUndoableChange("Edit MIDI") {
            persistProjectState()
            reconfigureMIDI()
        }
    }

    private func commitMIDIConfig() {
        try? modelContext.save()
        reconfigureMIDI()
    }

    private func createMIDITrack(for device: MIDIDevice) {
        for existing in midiTracks {
            existing.sortOrder += 1
        }
        let track = MIDITrack(
            displayName: device.name,
            sortOrder: 0
        )
        track.device = device
        track.song = song
        modelContext.insert(track)
        song.midiTracks.append(track)
        try? modelContext.save()
        reconfigureMIDI()
    }

    private func presentTrackImporter() {
        #if os(macOS)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = FileStore.supportedTypes
            panel.prompt = "Add"
            panel.message = "Choose audio files to add as tracks."
            guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
            importAudioTracks(from: panel.urls)
        }
        #else
        showingTrackImporter = true
        #endif
    }

    private func presentAbletonImporter() {
        #if os(macOS)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [AbletonProjectImporter.abletonLiveSetType]
            panel.prompt = "Import"
            panel.message = "Choose an Ableton Live Set."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            importAbletonFile(from: url)
        }
        #else
        showingAbletonImporter = true
        #endif
    }

    private func performPendingAddTrack() {
        guard let kind = pendingAddTrackKind else { return }
        pendingAddTrackKind = nil
        switch kind {
        case .audio:
            presentTrackImporter()
        case .midi:
            showingMIDIDevicePicker = true
        case .ableton:
            presentAbletonImporter()
        }
    }

    private func handleTrackImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            importAudioTracks(from: urls)
        }
    }

    private func handleAbletonImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importAbletonFile(from: url)
        }
    }

    private func importAudioTracks(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: modelContext)
            let tracks = try FileStore.linkTracks(
                from: urls,
                into: song,
                projectFileURL: projectURL
            )
            performUndoableChange("Add Track") {
                for track in tracks {
                    modelContext.insert(track)
                    song.tracks.append(track)
                    if let clip = SongProjectBridge.defaultClip(for: track, in: song) {
                        timeline.clips.append(clip)
                    }
                }
                try? modelContext.save()
                TrackGroupStore.autoAssignGroups(for: song, in: modelContext)
                persistProjectState()
                syncPlayback()
                viewModel.loadSong(context: modelContext)
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importAbletonFile(from url: URL) {
        do {
            let importResult = try AbletonProjectImporter.importFrom(url: url)
            let importedMarkers = AbletonProjectImporter.makeMarkers(from: importResult).sortedByTime
            performUndoableChange("Import Ableton File") {
                if !importedMarkers.isEmpty {
                    timeline.markers = importedMarkers
                }
                try? AbletonProjectImporter.apply(
                    importResult,
                    markers: importedMarkers,
                    to: song,
                    context: modelContext
                )
                tempoChanges = [TempoChange(startMeasure: 1, bpm: importResult.bpm, sortOrder: 0)]
                timeSignatureChanges = importResult.timeSignatures
                persistProjectState()
                syncPlayback()
                viewModel.syncTempoMap(tempoChanges, timeSignatureChanges: timeSignatureChanges)
                prepareSectionAnnouncements()
            }
            abletonImportSummary = abletonSummary(for: importResult)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func abletonSummary(for result: AbletonProjectImporter.ImportResult) -> String {
        let bpmText = String(format: "%.1f BPM", result.bpm)
        if result.sections.isEmpty {
            return "Imported tempo at \(bpmText)."
        }
        return "Imported \(result.sections.count) sections at \(bpmText)."
    }

    private func editDevice(for track: MIDITrack) {
        guard let device = track.device else {
            showingMIDIDevicePicker = true
            return
        }
        deviceBeingEdited = device
    }

    private func deleteMIDITrack(_ track: MIDITrack) {
        midiEvents.removeAll { $0.trackID == track.id }
        selectedTrackIDs.remove(track.id)
        song.midiTracks.removeAll { $0.id == track.id }
        modelContext.delete(track)
        try? modelContext.save()
        commitMIDIEvents()
    }

    private func sendMIDITest(for track: MIDITrack) {
        guard let device = track.device,
              let uniqueID = device.destinationUniqueID,
              let command = device.commands.first else { return }
        MIDIOutputService.shared.sendNoteTestNow(
            note: command.note,
            channel: device.midiChannel,
            toUniqueID: uniqueID
        )
    }

    private var emptyTracksPlaceholder: some View {
        VStack(spacing: AppSpacing.md) {
            AppEmptyState(
                title: "No Tracks",
                systemImage: "waveform",
                description: "Add a track, MIDI lane, or Ableton file to get started."
            )
            AppPrimaryButton(title: "Add Track") {
                showingAddTrackOptions = true
            }
        }
        .frame(maxHeight: .infinity)
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

    private var addTrackFlowModifier: AddTrackFlowModifier {
        AddTrackFlowModifier(
            showingTrackImporter: $showingTrackImporter,
            showingAbletonImporter: $showingAbletonImporter,
            importError: $importError,
            abletonImportSummary: $abletonImportSummary,
            onImportTracks: handleTrackImport,
            onImportAbleton: handleAbletonImport
        )
    }

    private var detectSectionsModifier: DetectSectionsFlowModifier {
        DetectSectionsFlowModifier(
            showingReplaceConfirm: $showingDetectSectionsConfirm,
            error: $sectionDetectionError,
            onConfirmReplace: detectSections
        )
    }

    var body: some View {
        editorRoot
        .background(Color.dawTimelineBackground)
        .focusable()
        .focused($isTimelineFocused)
        .focusEffectDisabled()
        .focusedValue(\.clipEditorActions, clipEditorActions)
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
#if os(iOS)
        .sheet(item: $tempoLanePrompt) { prompt in
            TempoChangePrompt(
                measure: prompt.measure,
                currentBPM: prompt.bpm,
                onCancel: { tempoLanePrompt = nil },
                onChange: { bpm in
                    applyTempoChange(prompt: prompt, bpm: bpm)
                }
            )
        }
#else
        .onChange(of: tempoLanePrompt?.id) { _, _ in
            syncTempoChangeWindow()
        }
        .onDisappear {
            TempoChangeWindowController.shared.close()
        }
#endif
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
#if os(macOS)
        .toolbar {
            EditSongToolbarContent(
                viewModel: viewModel,
                song: song,
                showingArrangementEditor: $showingArrangementEditor,
                showingTimeSignatureEditor: $showingTimeSignatureEditor,
                timeSignatureChanges: $timeSignatureChanges,
                normalizedTimeSignatureChanges: normalizedTimeSignatureChanges,
                onPersistTimeSignatureChanges: {
                    performUndoableChange("Edit Time Signature") {
                        persistTimeSignatureChanges()
                    }
                },
                normalizedTempoChanges: normalizedTempoChanges,
                onApplyTempo: applyReferenceTempo,
                onApplyBaseKey: applyBaseKey,
                showingChangeKey: $showingChangeKey,
                arrangementActions: arrangementActions,
                loopSectionIDs: loopSectionIDs,
                showingSongLibrary: $showingSongLibrary,
                showingGroupEditor: $showingGroupEditor,
                isDetectingSections: isDetectingSections,
                onDetectSections: requestDetectSections,
                onBack: onBack,
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
                onClickTrackGenerated: reloadTimelineFromProject
            )
        }
        .appLockToolbarDisplayMode()
#endif
    }

    private func removeClipSelection() {
        guard !clipSelection.isEmpty else { return }
        let ids = clipSelection.clipIDs
        commitTimelineEdit("Delete Clips") { timeline in
            ClipEditing.delete(clipIDs: ids, in: &timeline.clips)
        }
        clipSelection.deselectAll()
        clearMarkerCue(cancellingScheduledTransition: false)
    }

    // MARK: - Clip selection

    private func selectAllClips() {
        clipSelection = ClipSelection(timeline.clips.map(\.id))
    }

    /// Splits every selected clip that spans `time`; both halves stay selected.
    private func splitSelectedClips(at time: TimeInterval) {
        let ids = clipSelection.clipIDs
        guard timeline.clips.contains(where: { ids.contains($0.id) && $0.containsTimelineTime(time) }) else { return }
        commitTimelineEdit("Split Clips") { timeline in
            let rightIDs = ClipEditing.split(clipIDs: ids, at: time, in: &timeline.clips)
            clipSelection.select(rightIDs)
        }
    }

    private func joinSelectedClips() {
        var joined = timeline.clips
        let remaining = ClipEditing.join(clipIDs: clipSelection.clipIDs, in: &joined)
        guard joined != timeline.clips else { return }
        commitTimelineEdit("Join Clips") { timeline in
            timeline.clips = joined
        }
        clipSelection = ClipSelection(remaining)
    }

    private func duplicateSelectedClips() {
        guard !clipSelection.isEmpty else { return }
        let ids = clipSelection.clipIDs
        commitTimelineEdit("Duplicate Clips") { timeline in
            clipSelection = ClipSelection(ClipEditing.duplicate(clipIDs: ids, in: &timeline.clips))
        }
    }

    private var selectedClips: [TrackClip] {
        timeline.clips.filter { clipSelection.contains($0.id) }
    }

    private func snappedToBeat(_ time: TimeInterval) -> TimeInterval {
        MeasureTiming.snapToNearestBeat(
            max(0, time),
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
    }

    private var clipLaneActions: ClipLaneActions {
        ClipLaneActions(
            press: { clipID, trackID, modifiers in
                let wasSelected = clipSelection.press(clipID, extending: modifiers.shift)
                pendingShiftDeselectID = wasSelected ? clipID : nil
            },
            click: { clipID, modifiers, time in
                // A click is an insertion, so the range selection does not stay underneath it.
                editSelection = nil
                if pendingShiftDeselectID == clipID {
                    clipSelection.deselect(clipID)
                } else if modifiers.option {
                    splitSelectedClips(at: time)
                }
                pendingShiftDeselectID = nil
            },
            drag: updateClipDrag,
            endDrag: commitClipDrag,
            marquee: updateRangeDrag,
            endMarquee: {
                // Mouse-up keeps editSelection. Soundcraft leaves the range in place.
            },
            clickBlank: { trackID, time in
                editSelection = nil
                clipSelection.deselectAll()
                placeInsertion(on: trackID, at: time)
            },
            locate: { trackID, time in
                placeInsertion(on: trackID, at: time)
            },
            menu: performClipMenuAction
        )
    }

    /// Snaps the reference clip's moved edge to the beat grid and applies that change to the whole selection.
    private func updateClipDrag(_ request: ClipDragRequest) {
        pendingShiftDeselectID = nil
        switch request {
        case .move(let reference, let rawDelta, let copy):
            let earliest = selectedClips.map(\.timelineStartSeconds).min() ?? reference.timelineStartSeconds
            let delta = snappedToBeat(reference.timelineStartSeconds + rawDelta) - reference.timelineStartSeconds
            clipDrag = .move(delta: max(delta, -earliest), copy: copy)
        case .trim(let reference, let edge, let rawTime):
            let edgeTime = edge == .leading ? reference.timelineStartSeconds : reference.timelineEndSeconds
            clipDrag = .trim(edge: edge, delta: snappedToBeat(rawTime) - edgeTime)
        }
    }

    private func commitClipDrag() {
        guard let drag = clipDrag else { return }
        clipDrag = nil
        let ids = clipSelection.clipIDs
        switch drag {
        case .move(let delta, let copy):
            guard abs(delta) > ClipEditing.tolerance else { return }
            if copy {
                commitTimelineEdit("Copy Clips") { timeline in
                    clipSelection = ClipSelection(ClipEditing.copy(clipIDs: ids, by: delta, in: &timeline.clips))
                }
            } else {
                commitTimelineEdit("Move Clips") { timeline in
                    ClipEditing.move(clipIDs: ids, by: delta, in: &timeline.clips)
                }
            }
        case .trim(let edge, let delta):
            guard abs(delta) > ClipEditing.tolerance else { return }
            let durations = Dictionary(uniqueKeysWithValues: song.sortedTracks.map { ($0.id, viewModel.fileDuration(for: $0)) })
            commitTimelineEdit("Trim Clips") { timeline in
                ClipEditing.trim(
                    clipIDs: ids,
                    edge: edge,
                    by: delta,
                    sourceDuration: { durations[$0] ?? 0 },
                    in: &timeline.clips
                )
            }
        }
        clipSelection.retain(existing: timeline.clips)
    }

    /// A context-menu action on a clip outside the selection first makes it the only selected clip.
    private func performClipMenuAction(_ action: ClipMenuAction, clipID: UUID) {
        if !clipSelection.contains(clipID) {
            clipSelection = ClipSelection([clipID])
        }
        switch action {
        case .splitAtPlayhead: splitSelectedClips(at: AudioEngineManager.shared.currentTime)
        case .join: joinSelectedClips()
        case .duplicate: duplicateSelectedClips()
        case .delete: removeClipSelection()
        }
    }

    /// A Soundcraft selector drag: a snapped time range across every row from the press to the pointer.
    private struct ClipRangeDrag: Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var firstRow: Int
        var lastRow: Int
    }

    /// Rows run MIDI first, then audio. The drag selects each clip the range overlaps on those rows.
    private func updateRangeDrag(from start: CGPoint, to current: CGPoint, modifiers _: PointerModifiers) {
        let ids = displayedTrackIDs
        guard !ids.isEmpty else { return }
        let rowHeight = TimelineLayout.laneHeight + TimelineLayout.laneSpacing
        func row(at y: CGFloat) -> Int {
            let index = Int((y / rowHeight).rounded(.down))
            return min(max(index, 0), ids.count - 1)
        }
        let lowRow = min(row(at: start.y), row(at: current.y))
        let highRow = max(row(at: start.y), row(at: current.y))
        let startTime = snappedToBeat(time(atX: start.x))
        let endTime = snappedToBeat(time(atX: current.x))
        editSelection = ClipRangeDrag(
            start: min(startTime, endTime),
            end: max(startTime, endTime),
            firstRow: lowRow,
            lastRow: highRow
        )
        pendingShiftDeselectID = nil
        clipDrag = nil
        let trackIDs = Set(ids[lowRow...highRow])
        selectedTrackIDs = trackIDs
        clipSelection = ClipSelection(
            ClipSelection.clipIDs(
                in: timeline.clips,
                trackIDs: trackIDs,
                from: startTime,
                to: endTime
            )
        )
    }

    private func time(atX x: CGFloat) -> TimeInterval {
        TimelineLayout.time(at: x, duration: timelineDuration, contentWidth: timelineContentWidth)
    }

    private func clearMarkerCue(cancellingScheduledTransition: Bool = true) {
        if cancellingScheduledTransition, cuedSectionID != nil {
            viewModel.cancelScheduledSectionTransition()
        }
        cuedSectionID = nil
        cueFireTime = nil
        cueFlashPhase = false
    }

    private func prepareSectionAnnouncements() {
        guard song.smartGuideEnabled else { return }
        sectionAnnouncer.prepare(names: displaySections.map(\.name))
    }

    private func cueSection(_ section: SongSection) {
        sectionLoop.endLoopIfActive()

        if !audioEngine.isPlaying {
            clearMarkerCue()
            viewModel.seekAndPlay(to: section.timelineStartSeconds)
            return
        }

        if cuedSectionID == section.id {
            clearMarkerCue()
            return
        }

        cuedSectionID = section.id
        cueFireTime = sectionCueFireTime(for: section)

        guard viewModel.isLoaded else { return }
        viewModel.scheduleSectionTransition(
            to: section.timelineStartSeconds,
            at: cueFireTime ?? section.timelineStartSeconds
        )
    }

    private func sectionCueFireTime(for cuedSection: SongSection) -> TimeInterval {
        if let currentSection = displaySections.section(atTimeline: audioEngine.currentTime) {
            return currentSection.timelineEndSeconds
        }

        if audioEngine.currentTime < cuedSection.timelineStartSeconds {
            return cuedSection.timelineStartSeconds
        }

        return displaySections
            .map(\.timelineEndSeconds)
            .first(where: { $0 > audioEngine.currentTime })
            ?? cuedSection.timelineEndSeconds
    }

    private func fireMarkerCue() {
        guard let cueFireTime, let cuedSectionID else { return }
        guard audioEngine.currentTime >= cueFireTime || !audioEngine.hasPendingSectionTransition else { return }
        guard let section = displaySections.first(where: { $0.id == cuedSectionID }) else {
            clearMarkerCue(cancellingScheduledTransition: false)
            return
        }

        viewModel.snapToScheduledSection(section.timelineStartSeconds)
        clearMarkerCue(cancellingScheduledTransition: false)
    }

    private func toggleLoopSection(_ section: SongSection) {
        var loops = loopSectionIDs
        sectionLoop.toggleLoop(on: section.id, loopSectionIDs: &loops)
        commitTimelineEdit("Toggle Loop") { timeline in
            for index in timeline.markers.indices {
                timeline.markers[index].loops = loops.contains(timeline.markers[index].id)
            }
        }
    }

    private func addSection(at timelineTime: TimeInterval) {
        let snappedTime = MeasureTiming.snapToNearestBeat(
            max(0, timelineTime),
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let start = min(max(0, snappedTime), max(timelineDuration - 0.01, 0))
        guard !markers.contains(where: { abs($0.startSeconds - start) < 0.02 }) else { return }

        let newMarker = ArrangementMarker(
            name: "Section \(markers.count + 1)",
            startSeconds: start,
            sortOrder: markers.count
        )
        commitTimelineEdit("Add Section") { timeline in
            timeline.markers.append(newMarker)
        }

        if let section = displaySections.first(where: { $0.id == newMarker.id }) {
            sectionNamePromptTitle = "Name Section"
            sectionPendingRename = section
        }
    }

    private func requestDetectSections() {
        guard !isDetectingSections else { return }
        if markers.count > 1 {
            showingDetectSectionsConfirm = true
        } else {
            detectSections()
        }
    }

    private func detectSections() {
        guard !isDetectingSections else { return }
        let urls = SongSectionDetector.analysisTracks(in: song)
            .compactMap { FileStore.trackURL(for: song, track: $0) }
        let songDuration = timelineDuration
        isDetectingSections = true

        Task {
            defer { isDetectingSections = false }
            do {
                let starts = try await SongSectionDetector.detectSectionStarts(from: urls)
                let detected = SongSectionDetector.markers(
                    fromSectionStarts: starts,
                    songDuration: songDuration
                )
                guard detected.count > 1 else { throw SongSectionDetectorError.noSectionsFound }
                performUndoableChange("Detect Sections") {
                    applyDetectedSections(detected)
                }
            } catch {
                sectionDetectionError = error.localizedDescription
            }
        }
    }

    /// Replaces every marker. Clips are untouched.
    private func applyDetectedSections(_ detected: [ArrangementMarker]) {
        clearMarkerCue()
        timeline.markers = detected
        persistProjectState()
        syncPlayback()
        prepareSectionAnnouncements()
    }

    private func beginRenameSection(_ section: SongSection) {
        sectionNamePromptTitle = "Rename Section"
        sectionPendingRename = section
    }

    private func applySectionRename(_ newName: String) {
        guard let section = sectionPendingRename else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = timeline.markers.firstIndex(where: { $0.id == section.id }) else {
            sectionPendingRename = nil
            return
        }

        sectionPendingRename = nil
        commitTimelineEdit("Rename Section") { timeline in
            timeline.markers[index].name = trimmed
        }
    }

    /// Removes the marker only; the audio stays and joins the previous section.
    private func removeMarker(_ section: SongSection) {
        if cuedSectionID == section.id {
            clearMarkerCue()
        }
        commitTimelineEdit("Remove Marker") { timeline in
            timeline.markers.removeAll { $0.id == section.id }
        }
    }

    /// Removes the section's span from every track, MIDI lane, and the marker list, closing the gap.
    private func deleteSection(_ section: SongSection) {
        if cuedSectionID == section.id {
            clearMarkerCue()
        }
        clipSelection.deselectAll()
        performUndoableChange("Delete Section") {
            ClipEditing.removeSection(section.id, timeline: &timeline, midiEvents: &midiEvents)
            persistProjectState()
            syncPlayback()
            reconfigureMIDI()
            prepareSectionAnnouncements()
        }
    }

    private func duplicateSection(_ sectionID: UUID) {
        clipSelection.deselectAll()
        performUndoableChange("Duplicate Section") {
            ClipEditing.duplicateSection(sectionID, timeline: &timeline, midiEvents: &midiEvents)
            persistProjectState()
            syncPlayback()
            reconfigureMIDI()
            prepareSectionAnnouncements()
        }
    }

    private func moveSection(_ sectionID: UUID, toIndex index: Int) {
        clearMarkerCue()
        clipSelection.deselectAll()
        performUndoableChange("Reorder Sections") {
            ClipEditing.moveSection(sectionID, toIndex: index, timeline: &timeline, midiEvents: &midiEvents)
            persistProjectState()
            syncPlayback()
            reconfigureMIDI()
            prepareSectionAnnouncements()
        }
    }

    private var arrangementActions: ArrangementSectionActions {
        ArrangementSectionActions(
            sections: displaySections,
            move: moveSection(_:toIndex:),
            duplicate: duplicateSection,
            remove: { sectionID in
                guard let section = displaySections.first(where: { $0.id == sectionID }) else { return }
                deleteSection(section)
            }
        )
    }

    private func seekOnTimeline(to time: TimeInterval) {
        viewModel.seekAndPlay(to: time)
    }

    /// Where Play begins: the range start while a selection is showing, otherwise the insertion.
    private var playbackStart: TimeInterval {
        if let selection = editSelection, selection.end - selection.start > ClipEditing.tolerance {
            return selection.start
        }
        return insertionTime
    }

    /// Selector press records the insertion. Play is what moves the red playhead there.
    private func placeInsertion(on trackID: UUID, at time: TimeInterval) {
        insertionTime = max(0, time)
        selectedTrackIDs = [trackID]
    }

    private func playFromInsertion() {
        viewModel.seekAndPlay(to: playbackStart)
    }

    private func clampTimelineZoom() {
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
            song: song,
            timeSignatureChanges: $timeSignatureChanges,
            normalizedTimeSignatureChanges: normalizedTimeSignatureChanges,
            onPersistTimeSignatureChanges: {
                performUndoableChange("Edit Time Signature") {
                    persistTimeSignatureChanges()
                }
            },
            normalizedTempoChanges: normalizedTempoChanges,
            onApplyTempo: applyReferenceTempo,
            onApplyBaseKey: applyBaseKey,
            showingTimeSignatureEditor: $showingTimeSignatureEditor,
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
    private var editorRoot: some View {
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
            showingTimeSignatureEditor: $showingTimeSignatureEditor,
            timeSignatureChanges: $timeSignatureChanges,
            normalizedTimeSignatureChanges: normalizedTimeSignatureChanges,
            onPersistTimeSignatureChanges: {
                performUndoableChange("Edit Time Signature") {
                    persistTimeSignatureChanges()
                }
            },
            tempoChanges: $tempoChanges,
            normalizedTempoChanges: normalizedTempoChanges,
            onApplyTempo: applyReferenceTempo,
            onApplyBaseKey: applyBaseKey,
            showingChangeKey: $showingChangeKey,
            arrangementActions: arrangementActions,
            loopSectionIDs: loopSectionIDs,
            showingSongLibrary: $showingSongLibrary,
            showingGroupEditor: $showingGroupEditor,
            isDetectingSections: isDetectingSections,
            onDetectSections: requestDetectSections,
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
            laneCount: song.sortedTracks.count + midiTracks.count,
            timelineViewportWidth: $timelineViewportWidth,
            isTimelineFocused: $isTimelineFocused,
            ruler: { timelineRulerStack },
            timeRuler: { timelineTimeRuler },
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
                editingTimeSignatureMarkerID = marker.id
                showingTimeSignatureMarkerEditor = true
            },
            onDeleteTimeSignatureMarker: deleteTimeSignatureMarker,
            onTempoRulerTap: handleTempoRulerTap,
            onEditTempoMarker: { marker in
                tempoLanePrompt = TempoLanePrompt(
                    measure: marker.startMeasure,
                    bpm: marker.bpm,
                    markerID: marker.id
                )
            },
            onDeleteTempoMarker: deleteTempoMarker,
            onTempoOperations: { showingTempoOperations = true }
        )
        .frame(height: TimelineLayout.topRulerHeight)
        .id("\(displaySections.map(\.id))|\(timelineContentWidth)|\(normalizedTempoChanges.map(\.id))|\(normalizedTimeSignatureChanges.map(\.id))")
        .popover(isPresented: $showingTimeSignatureMarkerEditor, arrowEdge: .bottom) {
            if let markerID = editingTimeSignatureMarkerID,
               let marker = timeSignatureChanges.first(where: { $0.id == markerID }) {
                TimeSignatureMarkerEditorMenu(
                    marker: marker,
                    canDelete: marker.startMeasure > 1,
                    onApply: { numerator, denominator in
                        applyTimeSignatureMarker(
                            markerID: markerID,
                            numerator: numerator,
                            denominator: denominator
                        )
                    },
                    onDelete: {
                        if let marker = timeSignatureChanges.first(where: { $0.id == markerID }) {
                            deleteTimeSignatureMarker(marker)
                        }
                        showingTimeSignatureMarkerEditor = false
                        editingTimeSignatureMarkerID = nil
                    }
                )
            }
        }
        .popover(isPresented: $showingTempoOperations, arrowEdge: .bottom) {
            TempoOperationsMenu(
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                playhead: audioEngine.currentTime,
                onApply: applyTempoOperation
            )
        }
    }

    private func applyTempoOperation(_ changes: [TempoChange]) {
        performUndoableChange("Tempo Operation") {
            tempoChanges = changes
            persistTempoChanges()
            showingTempoOperations = false
        }
    }

    private var trackTimelineScrollContent: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.dawTimelineBackground)
                .frame(width: timelineDisplayWidth, height: trackAreaHeight)

            trackLanesContent
                .compositingGroup()
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
    }

    private var trackLanesContent: some View {
        LazyVStack(spacing: TimelineLayout.laneSpacing) {
            ForEach(midiTracks, id: \.id) { track in
                MIDILaneView(
                    track: track,
                    device: track.device,
                    timelineDuration: timelineDuration,
                    timelineContentWidth: timelineContentWidth,
                    laneHeight: TimelineLayout.laneHeight,
                    events: $midiEvents,
                    tempoChanges: normalizedTempoChanges,
                    timeSignatureChanges: normalizedTimeSignatureChanges,
                    onCommit: commitMIDIEvents
                )
                .frame(width: timelineContentWidth, alignment: .leading)
            }

            ForEach(Array(song.sortedTracks.enumerated()), id: \.element.id) { index, track in
                if let fileURL = FileStore.trackURL(for: song, track: track) {
                WaveformLaneView(
                    track: track,
                    fileURL: fileURL,
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
                    laneHeight: TimelineLayout.laneHeight,
                    rowIndex: midiTracks.count + index,
                    onCueSection: cueSection,
                    loopSectionIDs: loopSectionIDs,
                    onToggleLoopSection: toggleLoopSection,
                    shouldLoadWaveformPeaks: viewModel.isLoaded
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
            let rowHeight = TimelineLayout.laneHeight + TimelineLayout.laneSpacing
            ZStack(alignment: .topLeading) {
                ForEach(drag.firstRow...drag.lastRow, id: \.self) { row in
                    Rectangle()
                        .fill(Color.soundcraftSelection)
                        .frame(width: max(x1 - x0, 1), height: TimelineLayout.laneHeight)
                        .offset(x: x0, y: CGFloat(row) * rowHeight)
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
                rows: insertionRows,
                laneHeight: TimelineLayout.laneHeight,
                rowStride: TimelineLayout.laneHeight + TimelineLayout.laneSpacing,
                areaHeight: trackAreaHeight
            )
        }
    }

    /// MIDI lanes first, then audio, matching the header and lane order.
    private var displayedTrackIDs: [UUID] {
        midiTracks.map(\.id) + song.sortedTracks.map(\.id)
    }

    /// Clips as drawn, including an in-progress move or trim.
    private var previewClips: [TrackClip] {
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
        let rowHeight = TimelineLayout.laneHeight + TimelineLayout.laneSpacing
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
                y: CGFloat(row) * rowHeight,
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
                    laneHeight: TimelineLayout.laneHeight,
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
                    onDelete: { deleteMIDITrack(track) }
                )
            }

            ForEach(song.sortedTracks, id: \.id) { track in
                TrackLaneHeaderView(
                    track: track,
                    laneHeight: TimelineLayout.laneHeight,
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
                    }
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

    private var trackAreaHeight: CGFloat {
        let count = song.sortedTracks.count + midiTracks.count
        guard count > 0 else { return 0 }
        return CGFloat(count) * TimelineLayout.laneHeight
            + CGFloat(count - 1) * TimelineLayout.laneSpacing
    }

    private func beginRenameTrack(_ track: AudioTrack) {
        trackPendingRename = track
        renameTrackName = track.displayName
    }

    private func applyTrackRename() {
        guard let track = trackPendingRename else { return }
        let trimmed = renameTrackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            trackPendingRename = nil
            return
        }

        performUndoableChange("Rename Track") {
            track.displayName = trimmed
            try? modelContext.save()
            persistProjectState()
            trackPendingRename = nil
        }
    }

    private func deleteAudioTrack(_ track: AudioTrack) {
        let trackID = track.id

        performUndoableChange("Delete Track") {
            timeline.clips.removeAll { $0.trackID == trackID }
            clipSelection.retain(existing: timeline.clips)

            selectedTrackIDs.remove(trackID)

            song.tracks.removeAll { $0.id == trackID }
            modelContext.delete(track)

            for (index, remainingTrack) in song.sortedTracks.enumerated() {
                remainingTrack.sortOrder = index
            }

            persistProjectState()
            syncPlayback()
            viewModel.loadSong(context: modelContext)
        }
    }

    #if os(macOS)
    private func syncTempoChangeWindow() {
        guard let prompt = tempoLanePrompt else {
            TempoChangeWindowController.shared.close()
            return
        }
        TempoChangeWindowController.shared.show(
            measure: prompt.measure,
            bpm: prompt.bpm,
            onChange: { bpm in
                applyTempoChange(prompt: prompt, bpm: bpm)
            },
            onDismiss: {
                if tempoLanePrompt?.id == prompt.id {
                    tempoLanePrompt = nil
                }
            }
        )
    }
    #endif

    private func applyTempoChange(prompt: TempoLanePrompt, bpm: Double) {
        guard TempoChange.validBPMRange.contains(bpm) else { return }

        performUndoableChange("Edit Tempo") {
            if let markerID = prompt.markerID,
               tempoChanges.contains(where: { $0.id == markerID }) {
                tempoChanges = tempoChanges.map { change in
                    guard change.id == markerID else { return change }
                    return TempoChange(
                        id: change.id,
                        startMeasure: change.startMeasure,
                        beatOffset: change.beatOffset,
                        bpm: bpm,
                        sortOrder: change.sortOrder
                    )
                }
            } else {
                tempoChanges.append(TempoChange(startMeasure: prompt.measure, bpm: bpm))
            }
            persistTempoChanges()
            tempoLanePrompt = nil
        }
    }

    private func applyTimeSignatureMarker(markerID: UUID, numerator: Int, denominator: Int) {
        guard (1...32).contains(numerator),
              TimeSignatureChange.validDenominators.contains(denominator) else { return }

        performUndoableChange("Edit Time Signature") {
            timeSignatureChanges = timeSignatureChanges.map { change in
                guard change.id == markerID else { return change }
                return TimeSignatureChange(
                    id: change.id,
                    numerator: numerator,
                    denominator: denominator,
                    startMeasure: change.startMeasure,
                    sortOrder: change.sortOrder
                )
            }.normalizedEnsuringInitialMarker(
                defaultNumerator: measureNumerator,
                defaultDenominator: measureDenominator
            )

            persistTimeSignatureChanges()
            showingTimeSignatureMarkerEditor = false
            editingTimeSignatureMarkerID = nil
        }
    }

    private var trackHeaderRulerCorner: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: TimelineLayout.timeSignatureRulerHeight)

            Color.clear
                .frame(height: TimelineLayout.tempoRulerHeight)

            ZStack {
                HStack(spacing: 6) {
                    Text("Tracks")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button { showingAddTrackOptions = true } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                            Text("Add Track")
                        }
                        .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add Track")
                    .accessibilityLabel("Add Track")
                }
                .padding(.horizontal, 8)
            }
            .frame(height: TimelineLayout.sectionMarkerHeight)
        }
        .frame(width: TimelineLayout.trackHeaderWidth, height: TimelineLayout.topRulerHeight)
        .background(Color.dawTrackHeaderBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.dawTimelineDivider)
                .frame(height: 1)
        }
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
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.dawTimelineDivider)
                    .frame(width: 1)
            }
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
