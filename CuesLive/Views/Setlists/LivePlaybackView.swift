import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum SongImportFeedback: Identifiable {
    case success(String)
    case failure(String)

    var id: String {
        switch self {
        case .success(let message): "success-\(message)"
        case .failure(let message): "failure-\(message)"
        }
    }

    var title: String {
        switch self {
        case .success: "Complete"
        case .failure: "Failed"
        }
    }

    var message: String {
        switch self {
        case .success(let message), .failure(let message): message
        }
    }
}

private struct MissingMediaSheetContext: Identifiable {
    let id = UUID()
    let setlistID: UUID
    let focusedSongID: UUID?
    let missingTracks: [SongMediaHealth.MissingTrack]
}

struct LivePlaybackView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InputMappingController.self) private var mapping
    @Query(sort: \Song.name) private var allSongs: [Song]
    @Query(sort: \Setlist.lastOpenedAt, order: .reverse) private var allSetlists: [Setlist]

    @State private var activeSetlistID: UUID?
    @State private var didBootstrap = false
    @State private var coordinator = PlaybackCoordinator()
    @State private var viewModel = SetlistViewModel()
    @Bindable private var playbackClock = AudioEngineManager.shared
    @State private var cuedSectionID: UUID?
    @State private var cueFireTime: TimeInterval?
    @State private var cueFlashPhase = false
    @State private var sectionLoop = SectionLoopController()
    @State private var groupMixFade = GroupMixFadeController()
    @State private var sectionAnnouncer = SectionAnnouncer()
    @State private var showingSongLibrary = SongSidebarPreference.initialVisibility
    @State private var songToEditID: UUID?
    /// Song to open once the library sheet has dismissed, so the editor pushes as a screen.
    @State private var songPendingEditorID: UUID?
    @State private var showingManageOutputs = false
    @State private var showingShowFileImporter = false
    @State private var showingSetlistPackageExporter = false
    @State private var setlistPackageDocument: SetlistPackageFileDocument?
    @State private var showingShowFileExporter = false
    @State private var showFileDocument: ShowFileDocument?
    @State private var songImportFeedback: SongImportFeedback?
    @State private var isImportingSongFolder = false
    @State private var infoPanelHeight: CGFloat = 0
    @State private var mixerDetent: LiveGroupMixerDetent = .hidden
    @State private var headerPendingEdit: SetlistEntry?
    @State private var isCreatingHeader = false
    @State private var isEditingSetlist = false
    @State private var editHeaderTitle = ""
    @State private var editHeaderTimeSeconds: TimeInterval = 0
    @State private var overlapEditorContext: SetlistOverlapEditorContext?
    @State private var setlistRowMetrics = SetlistRowMetricsCache()
    @State private var showingMissingMediaAlert = false
    @State private var missingMediaSheet: MissingMediaSheetContext?
    @State private var ignoredMissingMediaPromptForSetlistID: UUID?
    @State private var mediaHealthRevision = 0
    @Bindable private var remoteHost = RemoteSessionHostService.shared
    private var remoteHostController: RemoteHostSessionController { .shared }

    private var activeSetlist: Setlist? {
        if let activeSetlistID,
           let setlist = allSetlists.first(where: { $0.id == activeSetlistID }) {
            return setlist
        }
        return allSetlists.first
    }

    /// Prefer `activeSetlist` in outer body modifiers; SwiftUI may evaluate them before bootstrap.
    private var workingSetlist: Setlist {
        activeSetlist!
    }

    var body: some View {
        Group {
            if let activeSetlist {
                playbackBody(for: activeSetlist)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            bootstrapSetlistIfNeeded()
            #if os(macOS)
            syncLiveSetlistMenuController()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            LiveSetlistMenuController.shared.reset()
            #endif
        }
        .onChange(of: activeSetlistID) { _, _ in
            #if os(macOS)
            syncLiveSetlistMenuController()
            #endif
        }
        .alert("Missing Audio Files", isPresented: $showingMissingMediaAlert) {
            Button("Relink…") {
                presentMissingMediaRelink(for: nil)
            }
            Button("Ignore", role: .cancel) {
                if let id = activeSetlistID {
                    ignoredMissingMediaPromptForSetlistID = id
                }
            }
        } message: {
            Text(missingMediaAlertMessage)
        }
        .sheet(item: $missingMediaSheet) { context in
            MissingMediaRelinkView(
                setlistID: context.setlistID,
                initialMissingTracks: context.missingTracks,
                focusedSongID: context.focusedSongID,
                onChanged: {
                    mediaHealthRevision += 1
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { headerPendingEdit != nil },
            set: { if !$0 { dismissHeaderEdit() } }
        )) {
            SetlistHeaderEditorSheet(
                navigationTitle: isCreatingHeader ? "New Header" : "Edit Header",
                confirmTitle: "Save",
                headerTitle: $editHeaderTitle,
                timeSeconds: $editHeaderTimeSeconds,
                onCancel: dismissHeaderEdit,
                onConfirm: saveHeaderEdit
            )
        }
    }

    private var missingMediaAlertMessage: String {
        guard let setlist = activeSetlist else {
            return "Some songs have missing audio files. Relink them now, or ignore and continue with warnings shown in the setlist."
        }
        let songs = SongMediaHealth.songsWithMissingMedia(in: setlist)
        let trackCount = SongMediaHealth.missingTracks(in: setlist).count
        let songLabel = songs.count == 1 ? "1 song has" : "\(songs.count) songs have"
        let trackLabel = trackCount == 1 ? "1 missing audio file" : "\(trackCount) missing audio files"
        return "\(songLabel) \(trackLabel). Relink them now, or ignore and continue with warnings shown in the setlist."
    }

    private func playbackBody(for setlist: Setlist) -> some View {
        playbackBodyLifecycle(
            for: setlist,
            content: playbackBodyPresentations(
                for: setlist,
                content: playbackBodyChrome(for: setlist)
            )
        )
    }

    private func playbackBodyChrome(for setlist: Setlist) -> some View {
        Group {
            #if os(macOS)
            LivePlaybackSidebarLayout(isVisible: $showingSongLibrary) {
                songLibraryPanel()
            } mainContent: {
                LivePlaybackTrailingSidebarLayout(isVisible: mapping.isMapping) {
                    InputMappingPanel()
                } mainContent: {
                    playbackMainLayout
                }
            }
            #else
            playbackMainLayout
            #endif
        }
        #if os(macOS)
        .navigationTitle(setlistDisplayName(for: setlist))
        .toolbarTitleMenu {
            setlistSwitcherMenuContent()
        }
        #else
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            playbackToolbar(for: setlist)
        }
        #if os(macOS)
        .appLockToolbarDisplayMode()
        #endif
        .appBackground(.primary)
        #if os(iOS)
        .sheet(isPresented: $showingManageOutputs) {
            DeviceSettingsSheet(onRoutingChanged: {
                applyOutputRoutingIfNotEditing()
            })
        }
        .sheet(isPresented: $showingSongLibrary) {
            AppSheetContainer {
                NavigationStack {
                    songLibraryPanel()
                }
            }
            .presentationDetents([.large])
        }
        #endif
    }

    private func playbackBodyPresentations<Content: View>(
        for setlist: Setlist,
        content: Content
    ) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if coordinator.isAudioOutputLost {
                    AudioOutputLostBanner(isUnresponsive: coordinator.isAudioOutputUnresponsive)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .outputRoutingDidChange)) { _ in
                applyOutputRoutingIfNotEditing()
            }
            .modifier(LiveRemoteHostSyncModifier(
                setlist: setlist,
                librarySignature: remoteLibrarySignature,
                coordinator: coordinator,
                sectionLoop: sectionLoop,
                groupMixFade: groupMixFade,
                cuedSectionID: cuedSectionID,
                cueFireTime: cueFireTime,
                remoteHostController: remoteHostController,
                isClientAuthenticated: remoteHost.isClientAuthenticated,
                sync: { syncRemoteHostSession(for: setlist) }
            ))
            .fileImporter(
                isPresented: $showingShowFileImporter,
                allowedContentTypes: [ProjectUTType.showProjectType],
                allowsMultipleSelection: false
            ) { result in
                handleShowFileImport(result)
            }
            .fileExporter(
                isPresented: $showingSetlistPackageExporter,
                document: setlistPackageDocument,
                contentType: .folder,
                defaultFilename: setlistPackageExportFileName
            ) { result in
                handleSetlistPackageExportResult(result)
            }
            .fileExporter(
                isPresented: $showingShowFileExporter,
                document: showFileDocument,
                contentType: ProjectUTType.showProjectType,
                defaultFilename: setlistSaveFileName
            ) { result in
                handleShowFileExportResult(result)
            }
            .sheet(item: $overlapEditorContext) { context in
                SetlistOverlapEditorView(
                    context: context,
                    onCommit: { config in
                        viewModel.setOverlapTransition(config, for: context.entry, context: modelContext)
                        coordinator.updateTransitions(from: workingSetlist)
                    }
                )
            }
            .alert(item: $songImportFeedback) { feedback in
                Alert(
                    title: Text(feedback.title),
                    message: Text(feedback.message),
                    dismissButton: .cancel(Text("OK"))
                )
            }
            .background {
                playbackMonitorSupport
            }
    }

    private func playbackBodyLifecycle<Content: View>(
        for setlist: Setlist,
        content: Content
    ) -> some View {
        content
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
            .onChange(of: coordinator.currentSong?.id) { _, _ in
                clearMarkerCue()
                sectionLoop.reset()
                groupMixFade.cancel()
                prepareSectionAnnouncements()
            }
            .onChange(of: coordinator.currentSong?.smartGuideEnabled ?? false) { _, _ in
                prepareSectionAnnouncements()
            }
            .task(id: sectionAnnouncementTaskID) {
                prepareSectionAnnouncements()
            }
            .onAppear {
                if activeSetlistID == nil {
                    activeSetlistID = setlist.id
                }
                coordinator.routingProvider = {
                    let channelCount = AudioOutputDeviceService.channelCount(
                        for: OutputRoutingStore.config(in: modelContext).selectedDeviceUID
                    )
                    return OutputRoutingStore.snapshot(in: modelContext, channelCount: channelCount)
                }
                coordinator.groupMixProvider = {
                    GroupMixStore.snapshot(in: modelContext)
                }
                coordinator.timecodeSettingsProvider = {
                    TimecodeSettingsStore.snapshot(in: modelContext)
                }
                coordinator.timecodeGroupIDProvider = {
                    TimecodePlaybackSupport.resolveGroupID(in: modelContext)
                }
                coordinator.configure(setlist: setlist)
                markSetlistOpened(setlist)
                promptForMissingMediaIfNeeded(in: setlist)
            }
            .onChange(of: activeSetlistID) { _, _ in
                #if os(iOS)
                showingSongLibrary = false
                #endif
                songPendingEditorID = nil
                songToEditID = nil
            }
            .onChange(of: showingSongLibrary) { _, isShowing in
                guard !isShowing, let pendingID = songPendingEditorID else { return }
                songPendingEditorID = nil
                Task { @MainActor in
                    songToEditID = pendingID
                }
            }
            .onDisappear {
                stopPlayback()
            }
            .onChange(of: songToEditID) { oldValue, newValue in
                if newValue != nil {
                    clearMarkerCue()
                    sectionLoop.reset()
                    groupMixFade.cancel()
                    coordinator.unbindPlaybackHandlers()
                    coordinator.pause()
                } else if let editedSongID = oldValue {
                    coordinator.refreshWaveformAfterEdit(for: editedSongID)
                }
                handleSongEditorDismissed(newValue)
            }
            .liveInputMappingSession(arePlaybackActionsEnabled: songToEditID == nil) { action in
                handleMappedLiveAction(action)
            }
            .navigationDestination(isPresented: songEditorDestination) {
                songEditorDestinationContent(for: setlist)
            }
    }

    private var playbackMainLayout: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            LivePlaybackMixerSplitLayout(
                mixerDetent: $mixerDetent,
                onLiveVolumeChange: { groupID, volume in
                    coordinator.applyProvisionalGroupVolume(groupID: groupID, volume: volume)
                },
                onMixChange: {
                    coordinator.updateGroupMix(context: modelContext)
                },
                mainContent: {
                    playbackMainSection
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LiveTransportBottomBar {
                transportStrip
            }
        }
        #else
        playbackMainSection
            .navigationDestination(isPresented: mixerScreenPresented) {
                LiveGroupMixerScreen(
                    onLiveVolumeChange: { groupID, volume in
                        coordinator.applyProvisionalGroupVolume(groupID: groupID, volume: volume)
                    },
                    onMixChange: {
                        coordinator.updateGroupMix(context: modelContext)
                    }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LiveTransportBottomBar {
                    transportStrip
                }
            }
        #endif
    }

    #if os(iOS)
    private var mixerScreenPresented: Binding<Bool> {
        Binding(
            get: { mixerDetent == .visible },
            set: { mixerDetent = $0 ? .visible : .hidden }
        )
    }
    #endif

    private var transportStrip: some View {
        LiveSetlistNowPlayingInfoView(
            coordinator: coordinator,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            isLoaded: coordinator.isLoaded && !coordinator.isLoadingSong,
            canLoop: !loopSections.isEmpty,
            infoPanelHeight: $infoPanelHeight,
            onStop: stopPlayback,
            onPlay: coordinator.play,
            onPause: coordinator.pause,
            onToggleLoop: toggleSectionLoop,
            onToggleFade: toggleGroupMixFade
        )
    }

    private func toggleGroupMixFade() {
        groupMixFade.toggleFade(context: modelContext) {
            coordinator.updateGroupMix(context: modelContext, persist: false)
        } onComplete: {
            coordinator.updateGroupMix(context: modelContext)
        }
    }

    private func songLibraryPanel() -> some View {
        SongLibraryPanel(
            onEdit: { song in
                presentSongEditor(for: song)
            },
            onDismiss: {
                showingSongLibrary = false
            },
            onFoldersSelected: { folderURLs in
                importSongs(from: folderURLs)
            },
            onAddToSetlist: { song in
                addSong(song, at: workingSetlist.sortedEntries.count)
            },
            isImportInProgress: isImportingSongFolder
        )
    }

    private func presentSongEditor(for song: Song) {
        #if os(iOS)
        if showingSongLibrary {
            songPendingEditorID = song.id
            showingSongLibrary = false
            return
        }
        #endif
        songToEditID = song.id
    }

    private var songEditorDestination: Binding<Bool> {
        Binding(
            get: { songToEditID != nil },
            set: { if !$0 { songToEditID = nil } }
        )
    }

    @ToolbarContentBuilder
    private func playbackToolbar(for setlist: Setlist) -> some ToolbarContent {
        LiveSetlistToolbarContent(
            setlistSwitcher: {
                #if os(macOS)
                EmptyView()
                #else
                setlistSwitcherMenu(for: setlist)
                #endif
            },
            coordinator: coordinator,
            showingManageOutputs: $showingManageOutputs,
            mixerDetent: $mixerDetent
        )
    }

    private func importSongs(from folderURLs: [URL]) {
        guard !isImportingSongFolder, !folderURLs.isEmpty else { return }

        isImportingSongFolder = true
        Task { @MainActor in
            defer { isImportingSongFolder = false }

            var importedSongs: [Song] = []
            var summaries: [String] = []
            var failureMessages: [String] = []

            for folderURL in folderURLs {
                do {
                    let importResult = try SongFolderImporter.importFromFolder(
                        at: folderURL,
                        context: modelContext
                    )
                    importedSongs.append(importResult.song)
                    summaries.append(SongFolderImporter.summaryMessage(for: importResult))
                } catch {
                    failureMessages.append(
                        folderURLs.count == 1
                            ? error.localizedDescription
                            : "\(folderURL.lastPathComponent): \(error.localizedDescription)"
                    )
                }
            }

            if !failureMessages.isEmpty {
                songImportFeedback = .failure(failureMessages.joined(separator: "\n"))
            } else if let song = importedSongs.first, importedSongs.count == 1 {
                // One new song: open it in the editor to get it ready, rather than confirming in an alert.
                presentSongEditor(for: song)
            } else {
                songImportFeedback = .success("Imported \(summaries.count) songs.")
            }
        }
    }

    private var setlistSaveFileName: String {
        let raw = (activeSetlist?.name ?? "Setlist")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = (raw.isEmpty || raw.caseInsensitiveCompare(Setlist.untitledName) == .orderedSame
            ? "Setlist"
            : raw)
            .components(separatedBy: invalid)
            .joined(separator: "-")
        return cleaned
    }

    private var setlistPackageExportFileName: String {
        let raw = (activeSetlist?.name ?? "Setlist")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = (raw.isEmpty ? "Setlist" : raw)
            .components(separatedBy: invalid)
            .joined(separator: "-")
        return cleaned
    }

    private func presentExportSetlistPackage() {
        guard activeSetlist != nil else { return }
        #if os(macOS)
        presentExportSetlistFolderMac()
        #else
        presentExportSetlistFolderExporter()
        #endif
    }

    #if os(macOS)
    private func presentExportSetlistFolderMac() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Export Setlist Folder"
        panel.message = "Creates a folder with the show file and a Songs folder."
        panel.nameFieldStringValue = setlistPackageExportFileName
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try SetlistPackageStore.export(
                setlist: workingSetlist,
                to: url,
                context: modelContext
            )
            songImportFeedback = .success("Exported setlist folder with songs, stems, clicks, and headers.")
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }
    #endif

    private func presentExportSetlistFolderExporter() {
        do {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("MTLExport-\(UUID().uuidString)", isDirectory: true)
            let packageURL = staging.appendingPathComponent(
                setlistPackageExportFileName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try SetlistPackageStore.export(
                setlist: workingSetlist,
                to: packageURL,
                context: modelContext
            )
            setlistPackageDocument = try SetlistPackageFileDocument(packageDirectory: packageURL)
            showingSetlistPackageExporter = true
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func handleSetlistPackageExportResult(_ result: Result<URL, Error>) {
        setlistPackageDocument = nil
        switch result {
        case .success:
            songImportFeedback = .success("Exported setlist folder with songs, stems, clicks, and headers.")
        case .failure(let error):
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func handleShowFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            songImportFeedback = .failure(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            openShowFile(at: url)
        }
    }

    private func presentOpen() {
        #if os(macOS)
        DispatchQueue.main.async {
            presentOpenSetlistPanel()
        }
        #else
        showingShowFileImporter = true
        #endif
    }

    #if os(macOS)
    private func presentOpenSetlistPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Open Setlist"
        panel.message = "Choose a cues.live setlist file (.cueshow)."
        panel.prompt = "Open"
        panel.allowedContentTypes = [ProjectUTType.showProjectType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openShowFile(at: url)
    }
    #endif

    private func openShowFile(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let setlist = try SongProjectBridge.importShow(from: url, into: modelContext)
            activateOpenedSetlist(setlist)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func activateOpenedSetlist(_ setlist: Setlist) {
        if setlist.id == activeSetlistID {
            clearMarkerCue()
            sectionLoop.reset()
            groupMixFade.cancel()
            coordinator.stop()
            markSetlistOpened(setlist)
            coordinator.configure(setlist: setlist)
            ignoredMissingMediaPromptForSetlistID = nil
            promptForMissingMediaIfNeeded(in: setlist)
        } else {
            ignoredMissingMediaPromptForSetlistID = nil
            switchToSetlist(setlist)
        }
    }

    private var playbackMonitorSupport: some View {
        LivePlaybackMonitorSupport(
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            onFireMarkerCue: fireMarkerCue,
            smartGuideEnabled: coordinator.currentSong?.smartGuideEnabled ?? false,
            sections: loopSections,
            announcer: sectionAnnouncer,
            sectionLoop: sectionLoop,
            loopSections: loopSections,
            loopSectionIDs: loopSectionIDs,
            playbackEngine: coordinator.playbackEngine,
            onLoopActivated: { clearMarkerCue() }
        )
    }

    private func prepareSectionAnnouncements() {
        guard coordinator.currentSong?.smartGuideEnabled == true else { return }
        sectionAnnouncer.prepare(names: loopSections.map(\.name))
    }

    private func toggleSectionLoop() {
        if sectionLoop.isLooping {
            sectionLoop.endLoop()
            return
        }

        guard let section = loopSections.section(atTimeline: coordinator.currentTime) else { return }
        clearMarkerCue()
        sectionLoop.beginManualLoop(sectionID: section.id)
    }

    private func handleMappedLiveAction(_ action: MappableLiveAction) {
        switch action {
        case .stop:
            stopPlayback()
        case .playPause:
            if coordinator.isPlaying {
                coordinator.pause()
            } else {
                coordinator.play()
            }
        case .fade:
            toggleGroupMixFade()
        case .loop:
            toggleSectionLoop()
        case .goToSong(let index):
            coordinator.goToSong(at: index, autoPlay: coordinator.isAudiblePlaying)
        }
    }

    private func syncRemoteHostSession(for setlist: Setlist) {
        remoteHostController.sync(
            setlist: setlist,
            coordinator: coordinator,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            modelContext: modelContext,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            clearMarkerCue: { cancelling in
                clearMarkerCue(cancellingScheduledTransition: cancelling)
            },
            cueSection: { section in
                cueSection(section)
            },
            fireMarkerCue: {
                fireMarkerCue()
            },
            stopPlayback: {
                stopPlayback()
            }
        )
    }

    private var remoteLibrarySignature: String {
        allSongs.map { song in
            "\(song.id.uuidString)|\(song.name)|\(song.tracks.count)|\(song.bpm ?? -1)|\(song.createdAt.timeIntervalSinceReferenceDate)|\(song.smartGuideEnabled)"
        }
        .joined(separator: ";")
    }

    @ViewBuilder
    private func songEditorDestinationContent(for setlist: Setlist) -> some View {
        if let songToEditID, let song = songForEditing(id: songToEditID) {
            SongDetailView(song: song)
        }
    }

    private func handleSongEditorDismissed(_ songToEditID: UUID?) {
        guard songToEditID == nil else { return }
        coordinator.bindPlaybackHandlers()
        coordinator.loadCurrentSong()
    }

    /// The song editor owns the shared engine while it is open.
    private func applyOutputRoutingIfNotEditing() {
        guard songToEditID == nil else { return }
        coordinator.applyOutputRouting()
    }

    private func setlistDisplayName(for setlist: Setlist) -> String {
        let trimmed = setlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Setlist" : trimmed
    }

    @ViewBuilder
    private func setlistSwitcherMenuContent() -> some View {
        ForEach(allSetlists) { candidate in
            Button {
                switchToSetlist(candidate)
            } label: {
                if candidate.id == activeSetlistID {
                    Label {
                        Text("\(candidate.name) · \(candidate.entries.count) songs")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text("\(candidate.name) · \(candidate.entries.count) songs")
                }
            }
        }

        Divider()

        Button {
            createUntitledSetlist()
        } label: {
            Label("New Setlist", systemImage: "plus")
        }

        Button {
            presentOpen()
        } label: {
            Label("Open…", systemImage: "folder")
        }

        Button {
            presentSave()
        } label: {
            Label("Save", systemImage: "tray.and.arrow.down")
        }

        Button {
            presentSaveAs()
        } label: {
            Label("Save As…", systemImage: "square.and.arrow.down.on.square")
        }

        Button {
            presentExportSetlistPackage()
        } label: {
            Label("Export Setlist Folder…", systemImage: "square.and.arrow.up")
        }
    }

    #if !os(macOS)
    private func setlistSwitcherMenu(for setlist: Setlist) -> some View {
        Menu {
            setlistSwitcherMenuContent()
        } label: {
            Text(setlistDisplayName(for: setlist))
                .fontWeight(.semibold)
        }
    }
    #endif

    private func bootstrapSetlistIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true

        guard allSetlists.isEmpty else {
            if activeSetlistID == nil {
                activeSetlistID = allSetlists.first?.id
            }
            return
        }

        let setlist = Setlist.untitledDraft()
        modelContext.insert(setlist)
        try? modelContext.save()
        activeSetlistID = setlist.id
    }

    #if os(macOS)
    private func syncLiveSetlistMenuController() {
        let hasSetlist = activeSetlist != nil
        LiveSetlistMenuController.shared.update(
            canSave: hasSetlist,
            save: presentSave,
            saveAs: presentSaveAs,
            canNew: hasSetlist,
            newSetlist: createUntitledSetlist,
            canOpen: true,
            open: presentOpen,
            canExportPackage: hasSetlist,
            exportPackage: presentExportSetlistPackage
        )
    }
    #endif

    private func switchToSetlist(_ setlist: Setlist) {
        guard setlist.id != activeSetlistID else { return }

        clearMarkerCue()
        sectionLoop.reset()
        groupMixFade.cancel()
        coordinator.stop()
        activeSetlistID = setlist.id
        markSetlistOpened(setlist)
        coordinator.configure(setlist: setlist)
        promptForMissingMediaIfNeeded(in: setlist)
    }

    private func promptForMissingMediaIfNeeded(in setlist: Setlist) {
        mediaHealthRevision += 1
        let missing = SongMediaHealth.missingTracks(in: setlist)
        guard !missing.isEmpty else { return }
        guard ignoredMissingMediaPromptForSetlistID != setlist.id else { return }
        showingMissingMediaAlert = true
    }

    private func presentMissingMediaRelink(for song: Song? = nil) {
        guard let setlist = activeSetlist else { return }
        let missing = SongMediaHealth.missingTracks(in: setlist)
        missingMediaSheet = MissingMediaSheetContext(
            setlistID: setlist.id,
            focusedSongID: song?.id,
            missingTracks: missing
        )
    }

    private func markSetlistOpened(_ setlist: Setlist) {
        setlist.lastOpenedAt = Date()
        try? modelContext.save()
    }

    private func stopPlayback() {
        clearMarkerCue()
        sectionLoop.reset()
        groupMixFade.clearFade(context: modelContext) {
            coordinator.updateGroupMix(context: modelContext)
        }
        coordinator.stop()
    }

    private func presentSave() {
        guard let setlist = activeSetlist else { return }
        if setlist.isDraft || setlist.showFilePath == nil {
            presentSaveLocationPicker(isSaveAs: false)
        } else {
            saveSetlistInPlace()
        }
    }

    private func presentSaveAs() {
        guard activeSetlist != nil else { return }
        presentSaveLocationPicker(isSaveAs: true)
    }

    private func presentSaveLocationPicker(isSaveAs: Bool) {
        #if os(macOS)
        DispatchQueue.main.async {
            presentSaveSetlistPanel(isSaveAs: isSaveAs)
        }
        #else
        presentSaveSetlistExporter()
        #endif
    }

    #if os(macOS)
    private func presentSaveSetlistPanel(isSaveAs: Bool) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = isSaveAs ? "Save Setlist As" : "Save Setlist"
        panel.message = "Choose a name and location for this setlist."
        panel.nameFieldLabel = "Name:"
        panel.nameFieldStringValue = setlistSaveFileName
        panel.allowedContentTypes = [ProjectUTType.showProjectType]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.prompt = "Save"
        if !isSaveAs {
            panel.directoryURL = ShowFileStore.showsDirectory
        } else if let path = activeSetlist?.showFilePath {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        commitSave(to: url)
    }
    #endif

    private func presentSaveSetlistExporter() {
        guard let setlist = activeSetlist else { return }
        do {
            let data = try SongProjectBridge.encodedShowData(for: setlist, context: modelContext)
            showFileDocument = ShowFileDocument(data: data)
            showingShowFileExporter = true
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func handleShowFileExportResult(_ result: Result<URL, Error>) {
        showFileDocument = nil
        switch result {
        case .success(let url):
            commitSave(to: url)
        case .failure(let error):
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func commitSave(to url: URL) {
        guard let setlist = activeSetlist else { return }
        setlist.name = ShowFileStore.displayName(fromShowURL: url)
        setlist.isDraft = false
        do {
            try modelContext.save()
            try SongProjectBridge.persistShow(for: setlist, to: url, context: modelContext)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func saveSetlistInPlace() {
        guard let setlist = activeSetlist else { return }
        do {
            try modelContext.save()
            try SongProjectBridge.persistShow(for: setlist, context: modelContext)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func createUntitledSetlist() {
        let newSetlist = Setlist.untitledDraft()
        modelContext.insert(newSetlist)
        try? modelContext.save()
        switchToSetlist(newSetlist)
    }

    private var setlistHasSongs: Bool {
        workingSetlist.sortedEntries.contains { $0.song != nil }
    }

    private var playbackMainSection: some View {
        #if os(macOS)
        Group {
            if setlistHasSongs {
                VSplitView {
                    currentSongSection
                        .background(AppColors.backgroundPrimary)

                    setlistSection
                        .background(AppColors.backgroundPrimary)
                }
            } else {
                setlistSection
                    .background(AppColors.backgroundPrimary)
            }
        }
        #else
        VStack(spacing: 0) {
            if setlistHasSongs {
                currentSongSection
                    .background(AppColors.backgroundPrimary)
            }

            setlistSection
                .background(AppColors.backgroundPrimary)
        }
        #endif
    }

    private var currentSongSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            LiveSetlistWaveformResizablePane(maxMIDILaneCount: coordinator.maxMIDILaneCount) {
                waveformContent
                    .padding(.top, AppSpacing.xs)
                    .overlay(alignment: .topLeading) { loadErrorBanner }
            }
            #else
            waveformContent
                .padding(.top, AppSpacing.xs)
                .overlay(alignment: .topLeading) { loadErrorBanner }
            #endif
        }
    }

    /// Overlaid rather than swapped in for the waveform so a failed load keeps the pane's height.
    @ViewBuilder
    private var loadErrorBanner: some View {
        // Missing audio is flagged on the sections themselves, so its load error stays hidden.
        if let loadError = coordinator.loadError,
           !(coordinator.currentSong.map(songHasMissingMedia) ?? false) {
            Label(loadError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .padding(AppSpacing.md)
        }
    }

    @ViewBuilder
    private var waveformContent: some View {
        if setlistHasSongs {
            LiveSetlistWaveformScrollView(
                timelineItems: coordinator.timelineItems,
                currentPlaybackIndex: coordinator.currentIndex,
                waveformSnapshotForSongID: { songID in
                    guard let song = coordinator.song(for: songID) else { return nil }
                    return coordinator.waveformSnapshot(for: song)
                },
                ensureWaveformSnapshotForSongID: { songID in
                    guard let song = coordinator.song(for: songID) else { return }
                    coordinator.ensureWaveformSnapshot(for: song)
                },
                songHasMissingMedia: { songID in
                    coordinator.song(for: songID).map(songHasMissingMedia) ?? false
                },
                playheadTimeProvider: { coordinator.livePlayheadTime() },
                isPlayingProvider: { coordinator.isPlaying },
                // Only observe clock time while idle so seeks move the marker without
                // rebuilding the setlist on every playhead tick during playback.
                idlePlayheadTime: playbackClock.isPlaying ? nil : playbackClock.currentTime,
                cuedSectionID: cuedSectionID,
                cueFlashPhase: cueFlashPhase,
                onSeek: coordinator.seek,
                onCueSection: cueSection,
                onOverlapBadgeTapped: { playbackIndex in
                    presentOverlapEditor(forPlaybackIndex: playbackIndex)
                },
                onSelectSong: { index, startTime in
                    clearMarkerCue()
                    sectionLoop.endLoopIfActive()
                    coordinator.goToSong(
                        at: index,
                        autoPlay: coordinator.isAudiblePlaying,
                        startTime: startTime
                    )
                },
                maxMIDILaneCount: coordinator.maxMIDILaneCount
            )
            .overlay {
                if coordinator.isLoadingSong {
                    loadingOverlay
                }
            }
        } else if coordinator.isLoadingSong {
            LiveSetlistWaveformLoadingPlaceholder(
                message: loadingMessage(for: coordinator.currentSong)
            )
        } else {
            LiveSetlistWaveformLoadingPlaceholder()
        }
    }

    private func loadingMessage(for song: Song?) -> String {
        guard let song, song.transposeHighQuality, song.transposeSemitones != 0 else {
            return "Loading audio…"
        }
        return "Processing audio…"
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
            ProgressView(loadingMessage(for: coordinator.currentSong))
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private struct LiveSetlistWaveformLoadingPlaceholder: View {
        var message: String?

        @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

        private var panelHeight: CGFloat {
            LiveSetlistWaveformMetrics.laneHeight(for: waveformHeight)
        }

        var body: some View {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppColors.backgroundPrimary)
                .overlay {
                    if let message {
                        ProgressView(message)
                            .tint(AppColors.accent)
                    } else {
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColors.separator, lineWidth: 0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: panelHeight)
                .redacted(reason: message == nil ? .placeholder : [])
        }
    }

    private var setlistSection: some View {
        VStack(spacing: 0) {
            LiveSetlistAddMenu(
                isEditing: workingSetlist.sortedEntries.isEmpty ? nil : $isEditingSetlist,
                onAddHeader: addHeader,
                onAddSong: { showingSongLibrary = true }
            )

            Group {
                if workingSetlist.sortedEntries.isEmpty {
                    AppEmptyState(
                        title: "No Songs in Setlist",
                        systemImage: "music.note.list",
                        description: "Use the add button or Songs library to build the setlist."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(AppSpacing.md)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { items, _ in
                        let ids = items.compactMap(SongDragPayload.songID(from:))
                        insertDroppedSongs(at: 0, songIDs: ids)
                        return !ids.isEmpty
                    }
                    .contextMenu {
                        Button {
                            addHeader()
                        } label: {
                            Label("Add Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                    }
                } else {
                    SetlistListView(
                        rows: setlistRowModels,
                        currentIndex: coordinator.currentIndex,
                        isPlaying: coordinator.isAudiblePlaying,
                        isEditing: $isEditingSetlist,
                        actions: setlistRowActions(for:),
                        onMove: moveSetlistRows,
                        onAddHeader: addHeader,
                        onInsertSongs: insertDroppedSongs
                    )
                    .frame(maxWidth: 720, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: workingSetlist.sortedEntries.isEmpty) { _, isEmpty in
            if isEmpty { isEditingSetlist = false }
        }
    }

    /// Entries that can be shown. A song deleted from the library leaves an entry with neither
    /// a song nor a header title; those are skipped, so row indices don't match `sortedEntries`.
    private var visibleSetlistEntries: [SetlistEntry] {
        workingSetlist.sortedEntries.filter { $0.isHeader || $0.song != nil }
    }

    private var setlistRowModels: [SetlistRowModel] {
        let setlist = workingSetlist
        return visibleSetlistEntries.compactMap { entry in
            if entry.isHeader {
                let seconds = entry.headerTimeSeconds ?? 0
                return SetlistRowModel(
                    id: entry.persistentModelID,
                    kind: .header(
                        title: entry.headerTitle ?? "",
                        timeText: seconds > 0 ? LiveSetlistDurationFormat.clock(for: seconds) : nil
                    )
                )
            }
            guard let song = entry.song else { return nil }
            return SetlistRowModel(
                id: entry.persistentModelID,
                kind: .song(SetlistRowModel.Song(
                    title: song.name,
                    durationText: LiveSetlistDurationFormat.clock(for: songTimelineDuration(for: song)),
                    keyText: song.displayedKeyText,
                    bpmText: song.bpm.map { String(format: "%.0f BPM", $0.rounded()) },
                    playbackIndex: setlist.playbackIndex(for: entry) ?? 0,
                    hasMissingMedia: songHasMissingMedia(song),
                    hasSmartGuide: song.smartGuideEnabled,
                    transition: setlist.hasNextSong(after: entry) ? entry.transition : nil
                ))
            )
        }
    }

    private func setlistRowActions(for model: SetlistRowModel) -> SetlistRowActions {
        guard let entry = visibleSetlistEntries.first(where: { AnyHashable($0.persistentModelID) == model.id }) else {
            return SetlistRowActions(remove: {})
        }

        guard case .song(let rowSong) = model.kind, let song = entry.song else {
            return SetlistRowActions(
                edit: { beginEditingHeader(entry) },
                remove: { removeFromSetlist(entry) }
            )
        }

        return SetlistRowActions(
            play: { coordinator.goToSong(at: rowSong.playbackIndex, autoPlay: coordinator.isAudiblePlaying) },
            edit: { presentSongEditor(for: song) },
            relink: rowSong.hasMissingMedia ? { presentMissingMediaRelink(for: song) } : nil,
            transitions: rowSong.transition == nil ? [] : availableTransitions(for: entry),
            setTransition: { handleTransitionSelection($0, for: entry) },
            remove: { removeFromSetlist(entry) }
        )
    }

    /// Translates list offsets (visible rows only) into offsets in the full sorted entry list.
    /// `rowIndex` is a position among the visible rows; map it to `sortedEntries` like `moveSetlistRows`.
    private func insertDroppedSongs(at rowIndex: Int, songIDs: [UUID]) {
        let sorted = workingSetlist.sortedEntries
        let visible = sorted.filter { $0.isHeader || $0.song != nil }
        var index = rowIndex < visible.count
            ? (sorted.firstIndex(where: { $0 === visible[rowIndex] }) ?? sorted.count)
            : sorted.count
        for id in songIDs {
            let descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
            guard let song = try? modelContext.fetch(descriptor).first else { continue }
            addSong(song, at: index)
            index += 1
        }
    }

    private func moveSetlistRows(from source: IndexSet, to destination: Int) {
        let sorted = workingSetlist.sortedEntries
        let visible = sorted.filter { $0.isHeader || $0.song != nil }
        let sourceOffsets = IndexSet(source.compactMap { offset in
            sorted.firstIndex(where: { $0 === visible[offset] })
        })
        let destinationOffset = destination < visible.count
            ? (sorted.firstIndex(where: { $0 === visible[destination] }) ?? sorted.count)
            : sorted.count
        viewModel.moveEntries(
            in: workingSetlist,
            from: sourceOffsets,
            to: destinationOffset,
            context: modelContext
        )
        coordinator.syncSetlist(workingSetlist)
    }

    private func beginEditingHeader(_ entry: SetlistEntry) {
        isCreatingHeader = false
        headerPendingEdit = entry
        editHeaderTitle = entry.headerTitle ?? ""
        editHeaderTimeSeconds = entry.headerTimeSeconds ?? 0
    }

    private func songHasMissingMedia(_ song: Song) -> Bool {
        setlistRowMetrics.hasMissingMedia(song, revision: mediaHealthRevision)
    }

    private func songTimelineDuration(for song: Song) -> TimeInterval {
        setlistRowMetrics.timelineDuration(
            for: song,
            snapshot: coordinator.waveformSnapshot(for: song)?.timelineDuration
        )
    }

    private func removeFromSetlist(_ entry: SetlistEntry) {
        viewModel.removeEntry(entry, from: workingSetlist, context: modelContext)
        coordinator.syncSetlist(workingSetlist)
    }

    private func canUseOverlap(for entry: SetlistEntry) -> Bool {
        workingSetlist.canConfigureOverlap(after: entry)
    }

    private func availableTransitions(for entry: SetlistEntry) -> [SetlistTransition] {
        SetlistTransition.allCases.filter { transition in
            transition != .overlap || canUseOverlap(for: entry)
        }
    }

    private func handleTransitionSelection(_ option: SetlistTransition, for entry: SetlistEntry) {
        if option == .overlap {
            presentOverlapEditor(for: entry)
            return
        }
        viewModel.setTransition(option, for: entry, context: modelContext)
        coordinator.updateTransitions(from: workingSetlist)
    }

    private func presentOverlapEditor(for entry: SetlistEntry) {
        guard canUseOverlap(for: entry),
              let outgoing = entry.song,
              let incoming = workingSetlist.nextSong(after: entry) else {
            return
        }
        overlapEditorContext = SetlistOverlapEditorContext(
            entry: entry,
            outgoingSong: outgoing,
            incomingSong: incoming,
            outgoingSnapshot: coordinator.waveformSnapshot(for: outgoing),
            incomingSnapshot: coordinator.waveformSnapshot(for: incoming)
        )
        coordinator.ensureWaveformSnapshot(for: outgoing)
        coordinator.ensureWaveformSnapshot(for: incoming)
    }

    private func presentOverlapEditor(forPlaybackIndex playbackIndex: Int) {
        guard let entry = workingSetlist.sortedEntries.first(where: {
            workingSetlist.playbackIndex(for: $0) == playbackIndex
        }) else {
            return
        }
        presentOverlapEditor(for: entry)
    }

    private func songForEditing(id: UUID) -> Song? {
        workingSetlist.sortedEntries.compactMap(\.song).first(where: { $0.id == id })
            ?? allSongs.first(where: { $0.id == id })
    }

    private func addSong(_ song: Song, at index: Int) {
        viewModel.insertSong(song, at: index, to: workingSetlist, context: modelContext)
        coordinator.syncSetlist(workingSetlist)
    }

    private func addHeader() {
        let index = workingSetlist.sortedEntries.count
        viewModel.insertHeader(title: "New Header", at: index, to: workingSetlist, context: modelContext)
        if let entry = workingSetlist.sortedEntries.last(where: { $0.isHeader }) {
            isCreatingHeader = true
            headerPendingEdit = entry
            editHeaderTitle = entry.headerTitle ?? "New Header"
            editHeaderTimeSeconds = entry.headerTimeSeconds ?? 0
        }
    }

    private func saveHeaderEdit() {
        guard let entry = headerPendingEdit else { return }
        let trimmed = editHeaderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.updateHeader(
            entry,
            title: trimmed,
            timeSeconds: editHeaderTimeSeconds,
            context: modelContext
        )
        dismissHeaderEdit()
    }

    private func dismissHeaderEdit() {
        headerPendingEdit = nil
        isCreatingHeader = false
    }

    private var loopSectionIDs: Set<UUID> {
        coordinator.currentWaveformSnapshot?.loopSectionIDs ?? []
    }

    private var loopSections: [SongSection] {
        coordinator.currentWaveformSnapshot?.sections ?? []
    }

    private var sectionAnnouncementTaskID: String {
        let songID = coordinator.currentSong?.id.uuidString ?? "none"
        let enabled = coordinator.currentSong?.smartGuideEnabled == true
        let names = loopSections.map(\.name).joined(separator: "|")
        return "\(songID)-\(enabled)-\(names)"
    }

    private func clearMarkerCue(cancellingScheduledTransition: Bool = true) {
        if cancellingScheduledTransition, cuedSectionID != nil {
            coordinator.cancelScheduledSectionTransition()
        }
        cuedSectionID = nil
        cueFireTime = nil
        cueFlashPhase = false
    }

    private func cueSection(_ section: SongSection) {
        sectionLoop.endLoopIfActive()

        if !coordinator.isPlaying {
            clearMarkerCue()
            coordinator.seek(to: section.timelineStartSeconds)
            return
        }

        if cuedSectionID == section.id {
            clearMarkerCue()
            return
        }

        cuedSectionID = section.id
        let fireTime = sectionCueFireTime(for: section)
        cueFireTime = fireTime

        guard coordinator.isLoaded else { return }
        coordinator.scheduleSectionTransition(
            to: section.timelineStartSeconds,
            at: fireTime
        )
    }

    private func sectionCueFireTime(for cuedSection: SongSection) -> TimeInterval {
        let sections = loopSections

        if let currentSection = sections.section(atTimeline: coordinator.currentTime) {
            return currentSection.timelineEndSeconds
        }

        return sections
            .map(\.timelineEndSeconds)
            .first(where: { $0 > coordinator.currentTime })
            ?? cuedSection.timelineEndSeconds
    }

    private func fireMarkerCue() {
        guard let cueFireTime, let cuedSectionID else { return }
        guard coordinator.currentTime >= cueFireTime || !coordinator.hasPendingSectionTransition else { return }
        guard let section = coordinator.currentWaveformSnapshot?.sections.first(where: { $0.id == cuedSectionID }) else {
            clearMarkerCue(cancellingScheduledTransition: false)
            return
        }
        coordinator.snapToScheduledSection(section.timelineStartSeconds)
        clearMarkerCue(cancellingScheduledTransition: false)
    }
}

#Preview {
    NavigationStack {
        LivePlaybackView()
    }
    .modelContainer(for: [Setlist.self, SetlistEntry.self, Song.self], inMemory: true)
}
