import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditView {
    var midiTracks: [MIDITrack] {
        song.sortedMIDITracks
    }

    func reconfigureMIDI() {
        let resolved = MIDIScheduler.scheduledEvents(events: midiEvents, tracks: midiTracks)
        AudioEngineManager.shared.configureMIDI(events: resolved)
    }

    func commitMIDIEvents() {
        performUndoableChange("Edit MIDI") {
            persistProjectState()
            reconfigureMIDI()
        }
    }

    func commitMIDIConfig() {
        try? modelContext.save()
        reconfigureMIDI()
    }

    func createMIDITrack(for device: MIDIDevice) {
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

    func presentAbletonImporter() {
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

    func performPendingAddTrack() {
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

    /// Each file becomes its own track. `timelineStart` is where the clip begins: the file picker
    /// uses the start of the song, and a Finder drop uses the edit insertion.
    private func importAudioTracks(
        from urls: [URL],
        at timelineStart: TimeInterval = 0,
        actionName: String = "Add Track",
        selectImported: Bool = false
    ) {
        guard !urls.isEmpty else { return }
        do {
            let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: modelContext)
            let tracks = try FileStore.linkTracks(
                from: urls,
                into: song,
                projectFileURL: projectURL
            )
            performUndoableChange(actionName) {
                for track in tracks {
                    modelContext.insert(track)
                    song.tracks.append(track)
                    if let clip = SongProjectBridge.defaultClip(for: track, in: song, timelineStart: timelineStart) {
                        timeline.clips.append(clip)
                    }
                }
                try? modelContext.save()
                TrackGroupStore.autoAssignGroups(for: song, in: modelContext)
                persistProjectState()
                syncPlayback()
                viewModel.loadSong(context: modelContext)
            }
            if selectImported {
                selectedTrackIDs = Set(tracks.map(\.id))
                clipSelection.deselectAll()
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Finder drop onto the editor. The insertion is read now, before the files finish loading.
    func performAudioFileDrop(_ providers: [NSItemProvider]) -> Bool {
        isAudioDropTargeted = false
        guard !providers.isEmpty else { return false }
        let timelineStart = playbackStart
        Task { @MainActor in
            let opened = await AudioFileDrop.openAudioFiles(from: providers)
            defer {
                for file in opened {
                    file.close()
                }
            }
            let urls = opened.map(\.url)
            guard !urls.isEmpty else {
                importError = "Drop audio files to place them on the timeline."
                return
            }
            importAudioTracks(
                from: urls,
                at: timelineStart,
                actionName: "Import Audio",
                selectImported: true
            )
        }
        return true
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

    func editDevice(for track: MIDITrack) {
        guard let device = track.device else {
            showingMIDIDevicePicker = true
            return
        }
        deviceBeingEdited = device
    }

    func deleteMIDITrack(_ track: MIDITrack) {
        midiEvents.removeAll { $0.trackID == track.id }
        selectedTrackIDs.remove(track.id)
        song.midiTracks.removeAll { $0.id == track.id }
        modelContext.delete(track)
        try? modelContext.save()
        commitMIDIEvents()
    }

    func sendMIDITest(for track: MIDITrack) {
        guard let device = track.device,
              let uniqueID = device.destinationUniqueID,
              let command = device.commands.first else { return }
        MIDIOutputService.shared.sendNoteTestNow(
            note: command.note,
            channel: device.midiChannel,
            toUniqueID: uniqueID
        )
    }

    var emptyTracksPlaceholder: some View {
        VStack(spacing: AppSpacing.md) {
            AppEmptyState(
                title: "No Tracks",
                systemImage: "waveform",
                description: emptyTracksDescription
            )
            AppPrimaryButton(title: "Add Track") {
                showingAddTrackOptions = true
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyTracksDescription: String {
        #if os(macOS)
        "Add a track, or drag audio files here. They land on new tracks at the insertion point."
        #else
        "Add a track, MIDI lane, or Ableton file to get started."
        #endif
    }

    var addTrackFlowModifier: AddTrackFlowModifier {
        AddTrackFlowModifier(
            showingTrackImporter: $showingTrackImporter,
            showingAbletonImporter: $showingAbletonImporter,
            importError: $importError,
            abletonImportSummary: $abletonImportSummary,
            onImportTracks: handleTrackImport,
            onImportAbleton: handleAbletonImport
        )
    }

    func beginRenameTrack(_ track: AudioTrack) {
        trackPendingRename = track
        renameTrackName = track.displayName
    }

    func applyTrackRename() {
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

    func deleteAudioTrack(_ track: AudioTrack) {
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
}
