import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

typealias UndoableChangeHandler = (_ actionName: String, _ change: () -> Void) -> Void

struct EditView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    let undoController: SongUndoController
    @Binding var arrangementMarkers: [ArrangementMarker]
    @Binding var arrangementSlots: [ArrangementSlot]
    @Binding var clipTrims: [ArrangementClipTrim]
    @Binding var removedClips: [ArrangementRemovedClip]
    @Binding var clipGaps: [ArrangementClipGap]
    @Binding var clipRegions: [ClipRegion]
    @Binding var loopSlotIDs: Set<UUID>
    @Binding var tempoChanges: [TempoChange]
    @Binding var timeSignatureChanges: [TimeSignatureChange]
    @Binding var midiEvents: [MIDIEvent]
    @Binding var showingSongLibrary: Bool
    @Binding var showingBakeSheet: Bool
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
    @State private var showingTempoEditor = false
    @State private var editingTempoMarkerID: UUID?
    @State private var showingTimeSignatureMarkerEditor = false
    @State private var editingTimeSignatureMarkerID: UUID?
    @State private var sectionPendingRename: ArrangementDisplaySection?
    @State private var sectionNamePromptTitle = "Rename Section"
    @State private var trackPendingRename: AudioTrack?
    @State private var renameTrackName = ""
    @State private var clipSelection: TimelineClipSelection?
    @State private var rulerMeasureSelection: MeasureRangeSelection?
    @State private var selectedTrackID: UUID?
    @FocusState private var isTimelineFocused: Bool
    @State private var cachedRulerSections: [ArrangementDisplaySection] = []
    @State private var cachedTrackSections: [UUID: [ArrangementDisplaySection]] = [:]
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
            if let index = tempoChanges.firstIndex(where: { $0.startMeasure == 1 }) {
                let existing = tempoChanges[index]
                tempoChanges[index] = TempoChange(
                    id: existing.id,
                    startMeasure: 1,
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
            markers: markers,
            arrangementSlots: arrangementSlots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            loopSlotIDs: loopSlotIDs,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            midiEvents: midiEvents,
            context: modelContext
        )
    }

    private func captureSnapshot() -> SongEditSnapshot {
        SongEditSnapshot.capture(
            song: song,
            markers: arrangementMarkers,
            arrangementSlots: arrangementSlots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            loopSlotIDs: loopSlotIDs,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents
        )
    }

    private func applySnapshot(_ snapshot: SongEditSnapshot) {
        arrangementMarkers = snapshot.markers
        arrangementSlots = snapshot.arrangementSlots
        clipTrims = snapshot.clipTrims
        removedClips = snapshot.removedClips
        clipGaps = snapshot.clipGaps
        clipRegions = snapshot.clipRegions
        loopSlotIDs = snapshot.loopSlotIDs
        midiEvents = snapshot.midiEvents

        snapshot.applyMetadata(to: song)
        let trackIDsBeforeApply = Set(song.sortedTracks.map(\.id))
        snapshot.applyTracks(to: song, context: modelContext)
        let trackIDsChanged = trackIDsBeforeApply != Set(song.sortedTracks.map(\.id))

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
            markers: markers,
            arrangementSlots: arrangementSlots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            loopSlotIDs: loopSlotIDs,
            tempoChanges: normalizedTempo,
            timeSignatureChanges: normalizedTimeSignature,
            midiEvents: midiEvents,
            context: modelContext
        )
        try? modelContext.save()

        refreshTimelineLayout()
        syncPlayback()
        viewModel.syncTempoMap(normalizedTempo, timeSignatureChanges: normalizedTimeSignature)

        for track in song.sortedTracks {
            viewModel.updateMix(for: track, context: modelContext)
            viewModel.updateTrim(for: track, context: modelContext)
        }

        reconfigureMIDI()

        if snapshot.songMetadata.transposeHighQuality {
            Task {
                await viewModel.applyKeyChange(context: modelContext, highQuality: true)
            }
        } else if snapshot.songMetadata.transposeSemitones != 0 {
            Task {
                await viewModel.applyKeyChange(context: modelContext, highQuality: false)
            }
        }

        if trackIDsChanged {
            viewModel.loadSong(context: modelContext)
        }
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

    private var undoableChange: UndoableChangeHandler {
        { actionName, change in
            performUndoableChange(actionName, change)
        }
    }

    private func handleTempoRulerTap(at time: TimeInterval) {
        let boundary = MeasureTiming.nearestMeasureBoundary(
            to: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )

        if let existing = normalizedTempoChanges.first(where: { $0.startMeasure == boundary.measure }) {
            editingTempoMarkerID = existing.id
        } else {
            let activeBPM = MeasureTiming.activeBPM(
                at: boundary.time,
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges
            )
            let newMarker = TempoChange(startMeasure: boundary.measure, bpm: activeBPM)
            tempoChanges = (normalizedTempoChanges + [newMarker]).normalizedEnsuringInitialMarker(
                defaultBPM: song.bpm ?? TempoChange.defaultBPM
            )
            editingTempoMarkerID = tempoChanges.first(where: { $0.startMeasure == boundary.measure })?.id
        }
        showingTempoEditor = true
    }

    private func deleteTempoMarker(_ marker: TempoChange) {
        guard marker.startMeasure > 1 else { return }
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
        arrangementMarkers.sortedByTime
    }

    private var sourceDuration: TimeInterval {
        song.sortedTracks
            .map { viewModel.fileDuration(for: $0) }
            .max() ?? finiteEngineDuration
    }

    private var finiteEngineDuration: TimeInterval {
        AudioEngineManager.shared.duration
    }

    private var sourceDurationForTrack: (UUID) -> TimeInterval {
        { trackID in
            guard let track = song.sortedTracks.first(where: { $0.id == trackID }) else { return 1 }
            return viewModel.fileDuration(for: track)
        }
    }

    private var rulerSections: [ArrangementDisplaySection] {
        cachedRulerSections
    }

    private func trackSections(for track: AudioTrack) -> [ArrangementDisplaySection] {
        cachedTrackSections[track.id] ?? []
    }

    private func layoutInputs() -> ArrangementLayoutInputs {
        SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: song.sortedTracks.map(\.id),
            sourceDurationForTrack: sourceDurationForTrack
        )
    }

    private func refreshTimelineLayout() {
        let layout = viewModel.buildArrangementLayout(
            markers: markers,
            slots: arrangementSlots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions
        )
        cachedRulerSections = layout.rulerSections
        cachedTrackSections = layout.trackSections
    }

    private func persistArrangement() {
        persistProjectState()
    }

    private func syncPlayback() {
        viewModel.syncArrangement(
            markers: markers,
            slots: arrangementSlots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions
        )
    }

    private func syncTrackPlayback(for trackID: UUID) {
        viewModel.syncTrackArrangement(
            trackID: trackID,
            markers: markers,
            slots: arrangementSlots,
            clipTrims: clipTrims,
            removedClips: removedClips,
            clipGaps: clipGaps,
            clipRegions: clipRegions,
            track: song.sortedTracks.first(where: { $0.id == trackID })
        )
    }

    private func commitTrackArrangementChange(for trackID: UUID) {
        refreshTimelineLayout()
        syncTrackPlayback(for: trackID)
    }

    private var displaySections: [ArrangementDisplaySection] {
        rulerSections
    }

    private func trackLaneSections(for track: AudioTrack) -> [ArrangementDisplaySection] {
        trackSections(for: track)
    }

    private func clipDisplaySections(for track: AudioTrack) -> [ArrangementDisplaySection] {
        let laneSections = trackLaneSections(for: track)
        if !laneSections.isEmpty {
            return laneSections
        }
        return SongArrangementStore.sourceTrackDisplaySections(
            trackID: track.id,
            trimStart: track.trimStartSeconds,
            trimEnd: track.trimEndSeconds ?? viewModel.fileDuration(for: track),
            clipGaps: clipGaps,
            clipRegions: clipRegions
        )
    }

    private var clipEditorActions: ClipEditorActions {
        ClipEditorActions(
            canSplit: clipSelection != nil,
            canJoin: clipSelection?.isWholeClip == true,
            split: { splitSelectedClipAtPlayhead() },
            join: { joinSelectedClipWithNext() }
        )
    }

    private var timelineDuration: TimeInterval {
        let hasTrackSections = cachedTrackSections.values.contains { !$0.isEmpty }
        if !displaySections.isEmpty || hasTrackSections {
            return SongArrangementStore.effectiveTimelineDuration(
                rulerSections: rulerSections,
                trackSections: cachedTrackSections
            )
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
                }
                try? modelContext.save()
                try? SongProjectBridge.syncProjectFile(for: song, context: modelContext)
                TrackGroupStore.autoAssignGroups(for: song, in: modelContext)
                persistProjectState()
                refreshTimelineLayout()
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
                    arrangementMarkers = importedMarkers
                    arrangementSlots = SongArrangementStore.defaultSlots(from: importedMarkers)
                    clipTrims = []
                    removedClips = []
                    clipGaps = []
                    clipRegions = []
                    loopSlotIDs = []
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
                refreshTimelineLayout()
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
            refreshTimelineLayout()
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
            if let trackID = newValue?.trackID {
                selectedTrackID = trackID
            }
            if newValue != nil {
                rulerMeasureSelection = nil
                isTimelineFocused = true
            }
        }
        .onChange(of: arrangementSlots) { _, _ in
            refreshTimelineLayout()
            syncPlayback()
            prepareSectionAnnouncements()
        }
        .onChange(of: arrangementMarkers) { _, _ in
            refreshTimelineLayout()
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
                loopSection: sectionLoop.activeSection(in: displaySections, loopSlotIDs: loopSlotIDs),
                announcer: sectionAnnouncer
            )
            SectionLoopPlaybackSupport(
                loopController: sectionLoop,
                sections: displaySections,
                loopSlotIDs: loopSlotIDs,
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
            if rulerMeasureSelection != nil {
                rippleDeleteSelectedMeasures()
            } else {
                removeClipSelection()
            }
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
                markers: markers,
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
                arrangementSlots: $arrangementSlots,
                clipTrims: $clipTrims,
                removedClips: $removedClips,
                clipGaps: $clipGaps,
                clipRegions: $clipRegions,
                loopSlotIDs: $loopSlotIDs,
                showingSongLibrary: $showingSongLibrary,
                showingBakeSheet: $showingBakeSheet,
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
                onPersistArrangement: {
                    performUndoableChange("Edit Arrangement") {
                        persistArrangement()
                    }
                },
                onUndoableChange: undoableChange,
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
        .appLockToolbarDisplayMode()
#endif
    }

    private func removeClipSelection() {
        guard let clipSelection else { return }
        let trackID = clipSelection.trackID
        let selection = clipSelection

        performUndoableChange("Delete Clip") {
            switch selection {
            case .whole(let clipID, let slotID, let trackID, _):
                deleteWholeClip(clipID: clipID, slotID: slotID, trackID: trackID)
            case .range(_, let slotID, let trackID, let start, let end):
                if !displaySections.isEmpty,
                   let track = song.sortedTracks.first(where: { $0.id == trackID }),
                   let slot = arrangementSlots.first(where: { $0.id == slotID }),
                   let marker = markers.first(where: { $0.id == slot.markerID }),
                   let section = trackLaneSections(for: track).first(where: { $0.slotID == slotID }) {
                    SongArrangementStore.deleteVisibleRange(
                        slotID: slotID,
                        trackID: trackID,
                        rangeStart: start,
                        rangeEnd: end,
                        sections: trackLaneSections(for: track),
                        marker: marker,
                        markers: markers,
                        tempoChanges: normalizedTempoChanges,
                        timeSignatureChanges: normalizedTimeSignatureChanges,
                        sourceDuration: viewModel.fileDuration(for: track),
                        clipTrims: &clipTrims,
                        removedClips: &removedClips,
                        clipGaps: &clipGaps,
                        clipRegions: &clipRegions,
                        columnStart: section.columnStartSeconds
                    )
                } else if let track = song.sortedTracks.first(where: { $0.id == trackID }) {
                    deleteSourceTrackRange(track: track, rangeStart: start, rangeEnd: end)
                }
            }

            self.clipSelection = nil
            clearMarkerCue(cancellingScheduledTransition: false)
            persistArrangement()
            commitTrackArrangementChange(for: trackID)
        }
    }

    /// Ripple-deletes the ruler measure selection: removes that span from every track and shifts
    /// all later content, tempo/time-signature changes, section markers, and MIDI events earlier.
    private func rippleDeleteSelectedMeasures() {
        guard let selection = rulerMeasureSelection else { return }

        performUndoableChange("Ripple Delete") {
            let tracks = song.sortedTracks.map { track in
                TimelineRippleStore.Track(
                    id: track.id,
                    trimStart: track.trimStartSeconds,
                    trimEnd: track.trimEndSeconds ?? viewModel.fileDuration(for: track),
                    sourceDuration: viewModel.fileDuration(for: track)
                )
            }

            let result = TimelineRippleStore.rippleDeleteMeasures(
                startMeasure: selection.startMeasure,
                endMeasure: selection.endMeasure,
                markers: &arrangementMarkers,
                slots: &arrangementSlots,
                clipTrims: clipTrims,
                removedClips: removedClips,
                clipGaps: &clipGaps,
                clipRegions: &clipRegions,
                loopSlotIDs: &loopSlotIDs,
                tempoChanges: &tempoChanges,
                timeSignatureChanges: &timeSignatureChanges,
                midiEvents: &midiEvents,
                tracks: tracks,
                defaultBPM: song.bpm ?? TempoChange.defaultBPM,
                defaultNumerator: song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator,
                defaultDenominator: song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
            )

            for track in song.sortedTracks where result.emptiedTrackIDs.contains(track.id) {
                track.trimEndSeconds = track.trimStartSeconds
                viewModel.updateTrim(for: track, context: modelContext)
            }

            rulerMeasureSelection = nil
            clipSelection = nil
            clearMarkerCue(cancellingScheduledTransition: false)

            refreshTimelineLayout()
            persistTempoChanges()
            persistTimeSignatureChanges()
            persistArrangement()
            reconfigureMIDI()
            syncPlayback()
        }
    }

    private func deleteWholeClip(clipID: UUID, slotID: UUID, trackID: UUID) {
        guard let track = song.sortedTracks.first(where: { $0.id == trackID }) else { return }

        let visibleSections = !displaySections.isEmpty
            ? trackLaneSections(for: track)
            : SongArrangementStore.sourceTrackDisplaySections(
                trackID: trackID,
                trimStart: track.trimStartSeconds,
                trimEnd: track.trimEndSeconds ?? viewModel.fileDuration(for: track),
                clipGaps: clipGaps,
                clipRegions: clipRegions
            )

        guard let section = visibleSections.first(where: { $0.id == clipID }) else { return }
        let siblingSections = visibleSections.filter { $0.slotID == slotID }

        if siblingSections.count > 1 {
            if !displaySections.isEmpty,
               let slot = arrangementSlots.first(where: { $0.id == slotID }),
               let marker = markers.first(where: { $0.id == slot.markerID }),
               let sourceRange = SongArrangementStore.trimmedSourceRange(
                   slot: slot,
                   trackID: trackID,
                   marker: marker,
                   markers: markers,
                   clipTrims: clipTrims,
                   sourceDuration: viewModel.fileDuration(for: track)
               ) {
                let bounds = SongArrangementStore.markerSourceRange(
                    for: marker,
                    markers: markers,
                    sourceDuration: viewModel.fileDuration(for: track)
                )
                SongArrangementStore.ensureClipRegions(
                    slotID: slotID,
                    trackID: trackID,
                    markerID: marker.id,
                    sourceRange: sourceRange,
                    boundsStart: bounds.start,
                    columnStart: section.columnStartSeconds,
                    clipGaps: clipGaps,
                    clipRegions: &clipRegions
                )
            } else {
                SongArrangementStore.ensureSourceTrackRegions(
                    trackID: track.id,
                    trimStart: track.trimStartSeconds,
                    trimEnd: track.trimEndSeconds ?? viewModel.fileDuration(for: track),
                    clipGaps: clipGaps,
                    clipRegions: &clipRegions
                )
            }
            clipGaps.removeAll { $0.slotID == slotID && $0.trackID == trackID }
            _ = SongArrangementStore.deleteRegion(
                regionID: clipID,
                slotID: slotID,
                trackID: trackID,
                clipTrims: &clipTrims,
                removedClips: &removedClips,
                clipGaps: &clipGaps,
                clipRegions: &clipRegions
            )
        } else if !displaySections.isEmpty {
            SongArrangementStore.removeClip(
                slotID: slotID,
                trackID: trackID,
                clipTrims: &clipTrims,
                removedClips: &removedClips,
                clipGaps: &clipGaps,
                clipRegions: &clipRegions
            )
        } else {
            deleteSourceTrackRange(
                track: track,
                rangeStart: section.sourceStartSeconds,
                rangeEnd: section.sourceEndSeconds
            )
        }
    }

    private func deleteSourceTrackRange(
        track: AudioTrack,
        rangeStart: TimeInterval,
        rangeEnd: TimeInterval
    ) {
        let fileDuration = viewModel.fileDuration(for: track)
        let clipStart = track.trimStartSeconds
        let clipEnd = track.trimEndSeconds ?? fileDuration
        let snapped = MeasureTiming.snapTimelineRangeToGrid(
            start: rangeStart,
            end: rangeEnd,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let selectionStart = max(snapped.start, clipStart)
        let selectionEnd = min(snapped.end, clipEnd)
        let minGap: TimeInterval = 0.1
        guard selectionEnd - selectionStart >= minGap else { return }

        let tolerance: TimeInterval = 0.02
        if selectionStart <= clipStart + tolerance, selectionEnd >= clipEnd - tolerance {
            track.trimEndSeconds = clipStart + minGap
        } else if selectionStart <= clipStart + tolerance {
            track.trimStartSeconds = min(selectionEnd, clipEnd - minGap)
        } else if selectionEnd >= clipEnd - tolerance {
            track.trimEndSeconds = max(selectionStart, clipStart + minGap)
        } else {
            SongArrangementStore.ensureSourceTrackRegions(
                trackID: track.id,
                trimStart: clipStart,
                trimEnd: clipEnd,
                clipGaps: clipGaps,
                clipRegions: &clipRegions
            )
            clipGaps.removeAll { $0.slotID == track.id && $0.trackID == track.id }
            _ = ClipRegionStore.deleteTimelineRange(
                slotID: track.id,
                trackID: track.id,
                rangeStart: selectionStart,
                rangeEnd: selectionEnd,
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                in: &clipRegions
            )
        }
        viewModel.updateTrim(for: track, context: modelContext)
    }

    private func splitSelectedClipAtPlayhead() {
        guard let selection = clipSelection else { return }
        let trackID = selection.trackID

        performUndoableChange("Split Clip") {
            switch selection {
            case .range(let clipID, let slotID, _, let start, let end):
                let minDuration = SongArrangementStore.minimumClipDuration
                if end - start < minDuration {
                    if let rightID = performSplit(
                        clipID: clipID,
                        slotID: slotID,
                        trackID: trackID,
                        at: start
                    ) {
                        clipSelection = .whole(clipID: rightID, slotID: slotID, trackID: trackID, editTime: nil)
                        finalizeSplit(trackID: trackID)
                    }
                    return
                }

                _ = performSplit(clipID: clipID, slotID: slotID, trackID: trackID, at: end)
                if let rightID = performSplit(clipID: clipID, slotID: slotID, trackID: trackID, at: start) {
                    clipSelection = .whole(clipID: rightID, slotID: slotID, trackID: trackID, editTime: nil)
                }
                finalizeSplit(trackID: trackID)

            case .whole(let clipID, let slotID, _, let editTime):
                let splitTime = editTime ?? AudioEngineManager.shared.currentTime
                if let rightID = performSplit(
                    clipID: clipID,
                    slotID: slotID,
                    trackID: trackID,
                    at: splitTime
                ) {
                    clipSelection = .whole(clipID: rightID, slotID: slotID, trackID: trackID, editTime: nil)
                    finalizeSplit(trackID: trackID)
                }
            }
        }
    }

    @discardableResult
    private func performSplit(
        clipID: UUID,
        slotID: UUID,
        trackID: UUID,
        at splitTime: TimeInterval
    ) -> UUID? {
        guard let track = song.sortedTracks.first(where: { $0.id == trackID }) else { return nil }

        let sections = clipDisplaySections(for: track)
        guard let section = sections.first(where: { $0.id == clipID })
            ?? sections.first(where: {
                splitTime >= $0.timelineStartSeconds + 0.02
                    && splitTime <= $0.timelineEndSeconds - 0.02
                    && $0.slotID == slotID
            }) else { return nil }
        guard splitTime > section.timelineStartSeconds + 0.02,
              splitTime < section.timelineEndSeconds - 0.02 else { return nil }

        if trackLaneSections(for: track).isEmpty {
            SongArrangementStore.ensureSourceTrackRegions(
                trackID: track.id,
                trimStart: track.trimStartSeconds,
                trimEnd: track.trimEndSeconds ?? viewModel.fileDuration(for: track),
                clipGaps: clipGaps,
                clipRegions: &clipRegions
            )
            clipGaps.removeAll { $0.slotID == track.id && $0.trackID == track.id }
        } else {
            materializeRegionsIfNeeded(
                slotID: slotID,
                trackID: trackID,
                section: section,
                track: track
            )
        }

        let regionID = ClipRegionStore.regions(slotID: slotID, trackID: trackID, in: clipRegions)
            .first(where: {
                splitTime > $0.timelineStartSeconds + 0.02
                    && splitTime < $0.timelineEndSeconds - 0.02
            })?.id ?? section.id

        return SongArrangementStore.splitRegion(
            regionID: regionID,
            trackID: trackID,
            at: splitTime,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            clipRegions: &clipRegions
        )
    }

    private func materializeRegionsIfNeeded(
        slotID: UUID,
        trackID: UUID,
        section: ArrangementDisplaySection,
        track: AudioTrack
    ) {
        guard !ClipRegionStore.hasStoredRegions(slotID: slotID, trackID: trackID, in: clipRegions),
              let slot = arrangementSlots.first(where: { $0.id == slotID }),
              let marker = markers.first(where: { $0.id == slot.markerID }),
              let sourceRange = SongArrangementStore.trimmedSourceRange(
                  slot: slot,
                  trackID: trackID,
                  marker: marker,
                  markers: markers,
                  clipTrims: clipTrims,
                  sourceDuration: viewModel.fileDuration(for: track)
              ) else { return }

        let bounds = SongArrangementStore.markerSourceRange(
            for: marker,
            markers: markers,
            sourceDuration: viewModel.fileDuration(for: track)
        )
        SongArrangementStore.ensureClipRegions(
            slotID: slotID,
            trackID: trackID,
            markerID: marker.id,
            sourceRange: sourceRange,
            boundsStart: bounds.start,
            columnStart: section.columnStartSeconds,
            clipGaps: clipGaps,
            clipRegions: &clipRegions
        )
        clipGaps.removeAll { $0.slotID == slotID && $0.trackID == trackID }
    }

    private func finalizeSplit(trackID: UUID) {
        refreshTimelineLayout()
        persistArrangement()
        commitTrackArrangementChange(for: trackID)
        syncPlayback()
    }

    private func joinSelectedClipWithNext() {
        guard case .whole(let clipID, let slotID, let trackID, _) = clipSelection else { return }
        guard let track = song.sortedTracks.first(where: { $0.id == trackID }) else { return }

        let sections = clipDisplaySections(for: track)
            .filter { $0.slotID == slotID }
            .sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }

        guard let index = sections.firstIndex(where: { $0.id == clipID }),
              index + 1 < sections.count else { return }

        let nextID = sections[index + 1].id

        performUndoableChange("Join Clips") {
            if let firstSection = sections.first, !trackLaneSections(for: track).isEmpty,
               let slot = arrangementSlots.first(where: { $0.id == slotID }),
               let marker = markers.first(where: { $0.id == slot.markerID }),
               let sourceRange = SongArrangementStore.trimmedSourceRange(
                   slot: slot,
                   trackID: trackID,
                   marker: marker,
                   markers: markers,
                   clipTrims: clipTrims,
                   sourceDuration: viewModel.fileDuration(for: track)
               ) {
                let bounds = SongArrangementStore.markerSourceRange(
                    for: marker,
                    markers: markers,
                    sourceDuration: viewModel.fileDuration(for: track)
                )
                SongArrangementStore.ensureClipRegions(
                    slotID: slotID,
                    trackID: trackID,
                    markerID: marker.id,
                    sourceRange: sourceRange,
                    boundsStart: bounds.start,
                    columnStart: firstSection.columnStartSeconds,
                    clipGaps: clipGaps,
                    clipRegions: &clipRegions
                )
            } else {
                SongArrangementStore.ensureSourceTrackRegions(
                    trackID: track.id,
                    trimStart: track.trimStartSeconds,
                    trimEnd: track.trimEndSeconds ?? viewModel.fileDuration(for: track),
                    clipGaps: clipGaps,
                    clipRegions: &clipRegions
                )
            }
            clipGaps.removeAll { $0.slotID == slotID && $0.trackID == trackID }

            if SongArrangementStore.joinRegions(
                firstID: clipID,
                secondID: nextID,
                trackID: trackID,
                clipRegions: &clipRegions
            ) != nil {
                persistArrangement()
                commitTrackArrangementChange(for: trackID)
            }
        }
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

    private func cueSection(_ section: ArrangementDisplaySection) {
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

    private func sectionCueFireTime(for cuedSection: ArrangementDisplaySection) -> TimeInterval {
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

    private func toggleLoopSection(_ section: ArrangementDisplaySection) {
        performUndoableChange("Toggle Loop") {
            sectionLoop.toggleLoop(on: section.id, loopSlotIDs: &loopSlotIDs)
            persistArrangement()
        }
    }

    private func addSection(at timelineTime: TimeInterval) {
        performUndoableChange("Add Section") {
            let snappedTime = MeasureTiming.snapToNearestBeat(
                max(0, timelineTime),
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges
            )
            let sourceTime = min(max(0, snappedTime), max(sourceDuration - 0.01, 0))

            if markers.contains(where: { abs($0.startSeconds - sourceTime) < 0.02 }) {
                return
            }

            let newMarker = ArrangementMarker(
                name: "Section \(markers.count + 1)",
                startSeconds: sourceTime,
                sortOrder: markers.count
            )
            let markerInsertIndex = markers.firstIndex(where: { $0.startSeconds > sourceTime + 0.001 })
                ?? markers.count

            arrangementMarkers.insert(newMarker, at: markerInsertIndex)

            let newSlot = ArrangementSlot(markerID: newMarker.id)
            let slotInsertIndex = displaySections.firstIndex(where: { timelineTime < $0.timelineStartSeconds - 0.001 })
                ?? arrangementSlots.count
            arrangementSlots.insert(newSlot, at: slotInsertIndex)

            refreshTimelineLayout()
            persistArrangement()
            syncPlayback()

            if let section = displaySections.first(where: { $0.markerID == newMarker.id }) {
                sectionNamePromptTitle = "Name Section"
                sectionPendingRename = section
            }
        }
    }

    private func addSection(from rawStart: TimeInterval, to rawEnd: TimeInterval) {
        let snapped = MeasureTiming.snapTimelineRangeToGrid(
            start: rawStart,
            end: rawEnd,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let songDuration = max(sourceDuration, 0)
        let start = min(max(0, snapped.start), songDuration)
        let end = min(max(0, snapped.end), songDuration)
        guard let plan = SectionRangeInsertion.plan(
            markers: markers,
            start: start,
            end: end,
            songDuration: songDuration,
            newSectionName: "Section \(markers.count + 1)"
        ) else { return }

        performUndoableChange("Add Section") {
            applySectionRangeInsertion(plan)
        }
    }

    private func applySectionRangeInsertion(_ plan: SectionRangeInsertion) {
        let removedMarkerIDs = Set(plan.removedMarkerIDs)
        let removedSlotIDs = Set(
            arrangementSlots
                .filter { removedMarkerIDs.contains($0.markerID) }
                .map(\.id)
        )

        if let cuedSectionID,
           displaySections.contains(where: {
               $0.id == cuedSectionID && removedMarkerIDs.contains($0.markerID)
           }) {
            clearMarkerCue()
        }

        for slotID in removedSlotIDs {
            loopSlotIDs.remove(slotID)
        }
        for section in displaySections where removedMarkerIDs.contains(section.markerID) {
            loopSlotIDs.remove(section.id)
            loopSlotIDs.remove(section.slotID)
        }

        clipTrims.removeAll { removedSlotIDs.contains($0.slotID) }
        removedClips.removeAll { removedSlotIDs.contains($0.slotID) }
        clipGaps.removeAll { removedSlotIDs.contains($0.slotID) }
        clipRegions.removeAll { removedSlotIDs.contains($0.slotID) }

        let wasIdentity = SongArrangementStore.isIdentitySlotSequence(
            arrangementSlots,
            markers: markers
        )
        var slotsByMarkerID: [UUID: ArrangementSlot] = [:]
        if wasIdentity {
            for slot in arrangementSlots where slotsByMarkerID[slot.markerID] == nil {
                slotsByMarkerID[slot.markerID] = slot
            }
        }

        arrangementMarkers = plan.markers

        if wasIdentity {
            arrangementSlots = plan.markers.map { marker in
                slotsByMarkerID[marker.id] ?? ArrangementSlot(markerID: marker.id)
            }
        } else {
            arrangementSlots.removeAll { removedMarkerIDs.contains($0.markerID) }
            let existingMarkerIDs = Set(arrangementSlots.map(\.markerID))
            let additions = plan.markers.filter { !existingMarkerIDs.contains($0.id) }
            for marker in additions {
                let index = arrangementSlots.firstIndex { slot in
                    guard let existing = plan.markers.first(where: { $0.id == slot.markerID }) else {
                        return false
                    }
                    return existing.startSeconds > marker.startSeconds + 0.001
                } ?? arrangementSlots.count
                arrangementSlots.insert(ArrangementSlot(markerID: marker.id), at: index)
            }
        }

        refreshTimelineLayout()
        persistArrangement()
        syncPlayback()

        if let section = displaySections.first(where: { $0.markerID == plan.sectionMarkerID }) {
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
        let songDuration = sourceDuration
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

    /// Replaces every section, which also drops the per-section clip edits and loops that pointed at them.
    private func applyDetectedSections(_ detected: [ArrangementMarker]) {
        clearMarkerCue()
        arrangementMarkers = detected
        arrangementSlots = detected.map { ArrangementSlot(markerID: $0.id) }
        clipTrims = []
        removedClips = []
        clipGaps = []
        clipRegions = []
        loopSlotIDs = []

        refreshTimelineLayout()
        persistArrangement()
        syncPlayback()
    }

    private func beginRenameSection(_ section: ArrangementDisplaySection) {
        sectionNamePromptTitle = "Rename Section"
        sectionPendingRename = section
    }

    private func applySectionRename(_ newName: String) {
        guard let section = sectionPendingRename else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = arrangementMarkers.firstIndex(where: { $0.id == section.markerID }) else {
            sectionPendingRename = nil
            return
        }

        performUndoableChange("Rename Section") {
            let marker = arrangementMarkers[index]
            arrangementMarkers[index] = ArrangementMarker(
                id: marker.id,
                name: trimmed,
                startSeconds: marker.startSeconds,
                sortOrder: marker.sortOrder
            )
            sectionPendingRename = nil
            refreshTimelineLayout()
            persistArrangement()
            syncPlayback()
        }
    }

    private func deleteSection(_ section: ArrangementDisplaySection) {
        performUndoableChange("Delete Section") {
            let slotID = section.slotID
            let markerID = section.markerID

            arrangementSlots.removeAll { $0.id == slotID }
            clipTrims.removeAll { $0.slotID == slotID }
            removedClips.removeAll { $0.slotID == slotID }
            clipGaps.removeAll { $0.slotID == slotID }
            clipRegions.removeAll { $0.slotID == slotID }
            loopSlotIDs.remove(slotID)
            loopSlotIDs.remove(section.id)

            if !arrangementSlots.contains(where: { $0.markerID == markerID }) {
                arrangementMarkers.removeAll { $0.id == markerID }
            }

            if cuedSectionID == section.id {
                clearMarkerCue()
            }

            refreshTimelineLayout()
            persistArrangement()
            syncPlayback()
        }
    }

    private func seekOnTimeline(to time: TimeInterval) {
        viewModel.seekAndPlay(to: time)
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
            loopSlotIDs: loopSlotIDs,
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
            }
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
            markers: markers,
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
            arrangementSlots: $arrangementSlots,
            clipTrims: $clipTrims,
            removedClips: $removedClips,
            clipGaps: $clipGaps,
            clipRegions: $clipRegions,
            loopSlotIDs: $loopSlotIDs,
            showingSongLibrary: $showingSongLibrary,
            showingBakeSheet: $showingBakeSheet,
            showingGroupEditor: $showingGroupEditor,
            isDetectingSections: isDetectingSections,
            onDetectSections: requestDetectSections,
            onClearMarkerCue: { clearMarkerCue() },
            onPersistArrangement: {
                performUndoableChange("Edit Arrangement") {
                    persistArrangement()
                }
            },
            onUndoableChange: undoableChange,
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
            timelineViewportWidth: $timelineViewportWidth,
            isTimelineFocused: $isTimelineFocused,
            ruler: { timelineRulerStack },
            lanes: { trackTimelineScrollContent },
            headerRulerCorner: { trackHeaderRulerCorner },
            headers: { trackHeaderList }
        )
        .simultaneousGesture(timelinePinchGesture)
    }

    private var timelineRulerStack: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.dawStickyRulerBackground)
                .frame(width: timelineDisplayWidth, height: TimelineLayout.rulerTotalHeight)

            ZStack(alignment: .topLeading) {
                timelineRulerSection

                TimelineMeasureGridOverlay(
                    duration: timelineDuration,
                    tempoChanges: normalizedTempoChanges,
                    timeSignatureChanges: normalizedTimeSignatureChanges,
                    contentWidth: timelineContentWidth,
                    displayWidth: timelineDisplayWidth,
                    rulerHeight: TimelineLayout.rulerTotalHeight
                )
                .allowsHitTesting(false)
            }
            .frame(width: timelineDisplayWidth, height: TimelineLayout.rulerTotalHeight, alignment: .leading)

            if let selectionRect = rulerSelectionRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.accentColor.opacity(0.8)).frame(width: 1)
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.accentColor.opacity(0.8)).frame(width: 1)
                    }
                    .frame(width: selectionRect.width, height: TimelineLayout.rulerTotalHeight)
                    .offset(x: selectionRect.minX)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: timelineDisplayWidth, height: TimelineLayout.rulerTotalHeight, alignment: .leading)
    }

    /// Pixel bounds of the ruler measure selection highlight, if any.
    private var rulerSelectionRect: (minX: CGFloat, width: CGFloat)? {
        guard let selection = rulerMeasureSelection else { return nil }
        let startTime = MeasureTiming.timeAtStartOfMeasure(
            selection.startMeasure,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let endTime = MeasureTiming.timeAtStartOfMeasure(
            selection.endMeasure,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let startX = TimelineLayout.xPosition(
            for: startTime,
            duration: timelineDuration,
            contentWidth: timelineContentWidth
        )
        let endX = TimelineLayout.xPosition(
            for: endTime,
            duration: timelineDuration,
            contentWidth: timelineContentWidth
        )
        return (startX, max(0, endX - startX))
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
            loopSlotIDs: loopSlotIDs,
            sectionMarkerHeight: TimelineLayout.sectionMarkerHeight,
            timeSignatureRulerHeight: TimelineLayout.timeSignatureRulerHeight,
            tempoRulerHeight: TimelineLayout.tempoRulerHeight,
            rulerHeight: TimelineLayout.rulerHeight,
            isPlaying: audioEngine.isPlaying,
            measureSelectionEnabled: !displaySections.isEmpty,
            onSeek: { time in
                rulerMeasureSelection = nil
                clearMarkerCue()
                seekOnTimeline(to: time)
            },
            onSelectMeasures: { startMeasure, endMeasure in
                clipSelection = nil
                rulerMeasureSelection = MeasureRangeSelection(
                    startMeasure: startMeasure,
                    endMeasure: endMeasure
                )
                isTimelineFocused = true
            },
            onCueSection: cueSection,
            onToggleLoopSection: toggleLoopSection,
            onAddSection: addSection,
            onAddSectionRange: addSection(from:to:),
            snapSectionRange: { start, end in
                MeasureTiming.snapTimelineRangeToGrid(
                    start: start,
                    end: end,
                    tempoChanges: normalizedTempoChanges,
                    timeSignatureChanges: normalizedTimeSignatureChanges
                )
            },
            onRenameSection: beginRenameSection,
            onDeleteSection: deleteSection,
            onTimeSignatureRulerTap: handleTimeSignatureRulerTap,
            onEditTimeSignatureMarker: { marker in
                editingTimeSignatureMarkerID = marker.id
                showingTimeSignatureMarkerEditor = true
            },
            onDeleteTimeSignatureMarker: deleteTimeSignatureMarker,
            onTempoRulerTap: handleTempoRulerTap,
            onEditTempoMarker: { marker in
                editingTempoMarkerID = marker.id
                showingTempoEditor = true
            },
            onDeleteTempoMarker: deleteTempoMarker
        )
        .frame(height: TimelineLayout.rulerTotalHeight)
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
        .popover(isPresented: $showingTempoEditor, arrowEdge: .bottom) {
            if let markerID = editingTempoMarkerID,
               let marker = tempoChanges.first(where: { $0.id == markerID }) {
                TempoMarkerEditorMenu(
                    marker: marker,
                    canDelete: marker.startMeasure > 1,
                    onApply: { bpm in
                        applyTempoMarker(markerID: markerID, bpm: bpm)
                    },
                    onDelete: {
                        if let marker = tempoChanges.first(where: { $0.id == markerID }) {
                            deleteTempoMarker(marker)
                        }
                        showingTempoEditor = false
                        editingTempoMarkerID = nil
                    }
                )
            }
        }
    }

    private var trackTimelineScrollContent: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.dawTimelineBackground)
                .frame(width: timelineDisplayWidth, height: trackAreaHeight)

            TimelineMeasureGridOverlay(
                duration: timelineDuration,
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                contentWidth: timelineContentWidth,
                displayWidth: timelineDisplayWidth,
                rulerHeight: 0
            )

            trackLanesContent
                .compositingGroup()
                .frame(width: timelineContentWidth, alignment: .leading)
        }
        .frame(width: timelineDisplayWidth, height: trackAreaHeight, alignment: .leading)
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

            ForEach(song.sortedTracks, id: \.id) { track in
                if let fileURL = FileStore.trackURL(for: song, track: track) {
                WaveformLaneView(
                    track: track,
                    fileURL: fileURL,
                    fileDuration: viewModel.fileDuration(for: track),
                    timelineDuration: timelineDuration,
                    timelineContentWidth: timelineContentWidth,
                    arrangementSections: trackLaneSections(for: track),
                    arrangementSlots: $arrangementSlots,
                    clipTrims: $clipTrims,
                    clipGaps: $clipGaps,
                    clipRegions: $clipRegions,
                    clipSelection: $clipSelection,
                    selectedTrackID: $selectedTrackID,
                    markers: markers,
                    tempoChanges: normalizedTempoChanges,
                    timeSignatureChanges: normalizedTimeSignatureChanges,
                    laneHeight: TimelineLayout.laneHeight,
                    onTrimChange: {
                        performUndoableChange("Trim Track") {
                            viewModel.updateTrim(for: track, context: modelContext)
                        }
                    },
                    onCueSection: cueSection,
                    loopSlotIDs: loopSlotIDs,
                    onToggleLoopSection: toggleLoopSection,
                    onClipTrimCommitted: {
                        performUndoableChange("Trim Clip") {
                            persistArrangement()
                            commitTrackArrangementChange(for: track.id)
                        }
                    },
                    onSeek: { time in
                        AudioEngineManager.shared.seek(to: time)
                    },
                    shouldLoadWaveformPeaks: viewModel.isLoaded
                )
                .frame(width: timelineContentWidth, alignment: .leading)
                }
            }
        }
        .frame(width: timelineContentWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var trackHeaderList: some View {
        LazyVStack(spacing: TimelineLayout.laneSpacing) {
            ForEach(midiTracks, id: \.id) { track in
                MIDITrackHeaderView(
                    track: track,
                    laneHeight: TimelineLayout.laneHeight,
                    isSelected: selectedTrackID == track.id,
                    onSelect: {
                        selectedTrackID = track.id
                        clipSelection = nil
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
                    isSelected: selectedTrackID == track.id,
                    groups: trackGroups,
                    onSelect: {
                        selectedTrackID = track.id
                        clipSelection = nil
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
        .overlay(alignment: .leading) {
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

    private func removeArrangementData(for trackID: UUID) {
        clipTrims.removeAll { $0.trackID == trackID || $0.slotID == trackID }
        removedClips.removeAll { $0.trackID == trackID || $0.slotID == trackID }
        clipGaps.removeAll { $0.trackID == trackID || $0.slotID == trackID }
        clipRegions.removeAll { $0.trackID == trackID || $0.slotID == trackID }
        loopSlotIDs.remove(trackID)
    }

    private func deleteAudioTrack(_ track: AudioTrack) {
        let trackID = track.id

        performUndoableChange("Delete Track") {
            removeArrangementData(for: trackID)

            if selectedTrackID == trackID {
                selectedTrackID = nil
            }
            if clipSelection?.trackID == trackID {
                clipSelection = nil
            }

            song.tracks.removeAll { $0.id == trackID }
            modelContext.delete(track)

            for (index, remainingTrack) in song.sortedTracks.enumerated() {
                remainingTrack.sortOrder = index
            }

            persistProjectState()
            refreshTimelineLayout()
            syncPlayback()
            viewModel.loadSong(context: modelContext)
        }
    }

    private func applyTempoMarker(markerID: UUID, bpm: Double) {
        guard TempoChange.validBPMRange.contains(bpm) else { return }

        performUndoableChange("Edit Tempo") {
            tempoChanges = tempoChanges.map { change in
                guard change.id == markerID else { return change }
                return TempoChange(
                    id: change.id,
                    startMeasure: change.startMeasure,
                    bpm: bpm,
                    sortOrder: change.sortOrder
                )
            }.normalizedEnsuringInitialMarker(defaultBPM: song.bpm ?? TempoChange.defaultBPM)

            persistTempoChanges()
            showingTempoEditor = false
            editingTempoMarkerID = nil
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
                .frame(height: TimelineLayout.sectionMarkerHeight)

            Color.clear
                .frame(height: TimelineLayout.timeSignatureRulerHeight)

            Color.clear
                .frame(height: TimelineLayout.tempoRulerHeight)

            ZStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))

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
            .frame(height: TimelineLayout.rulerHeight)
        }
        .frame(width: TimelineLayout.trackHeaderWidth, height: TimelineLayout.rulerTotalHeight)
        .background(Color.dawTrackHeaderBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.dawTimelineDivider)
                .frame(height: 1)
        }
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
        arrangementMarkers: .constant([]),
        arrangementSlots: .constant([]),
        clipTrims: .constant([]),
        removedClips: .constant([]),
        clipGaps: .constant([]),
        clipRegions: .constant([]),
        loopSlotIDs: .constant([]),
        tempoChanges: .constant([TempoChange(startMeasure: 1, bpm: 120)]),
        timeSignatureChanges: .constant([
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1, sortOrder: 0)
        ]),
        midiEvents: .constant([]),
        showingSongLibrary: .constant(false),
        showingBakeSheet: .constant(false)
    )
}
