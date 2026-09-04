import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
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
    @State private var showingSongLibrary = false
    @State private var songToEditID: UUID?
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
    @State private var editHeaderTitle = ""
    @State private var overlapEditorContext: SetlistOverlapEditorContext?
    @State private var draggedSetlistEntryID: PersistentIdentifier?
    @State private var hasPendingSetlistReorder = false
    @State private var showingMissingMediaAlert = false
    @State private var missingMediaSheet: MissingMediaSheetContext?
    @State private var ignoredMissingMediaPromptForSetlistID: UUID?
    @State private var mediaHealthRevision = 0
    @Bindable private var remoteHost = RemoteSessionHostService.shared
    private var remoteHostController: RemoteHostSessionController { .shared }

    #if os(iOS)
    private var placesTransportControlsAtBottom: Bool {
        LiveTransportLayout.placesControlsAtBottom(
            verticalSizeClass: verticalSizeClass,
            horizontalSizeClass: horizontalSizeClass
        )
    }
    #else
    private var placesTransportControlsAtBottom: Bool { false }
    #endif

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
        .alert("Edit Header", isPresented: Binding(
            get: { headerPendingEdit != nil },
            set: { if !$0 { headerPendingEdit = nil } }
        )) {
            TextField("Header title", text: $editHeaderTitle)
            Button("Save") {
                saveHeaderEdit()
            }
            Button("Cancel", role: .cancel) {
                headerPendingEdit = nil
            }
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
            LivePlaybackTrailingSidebarLayout(isVisible: mapping.isMapping) {
                InputMappingPanel()
            } mainContent: {
                LivePlaybackSidebarLayout(isVisible: $showingSongLibrary) {
                    songLibraryPanel()
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
        .toolbarBackground(AppColors.backgroundPrimary, for: .windowToolbar)
        .modifier(LivePlaybackMacToolbarBackgroundVisibilityModifier())
        .appLockToolbarDisplayMode()
        #endif
        .appBackground(.primary)
        #if os(iOS)
        .sheet(isPresented: $showingManageOutputs) {
            DeviceSettingsSheet(onRoutingChanged: {
                coordinator.applyOutputRouting()
            })
        }
        .sheet(isPresented: $showingSongLibrary) {
            AppSheetContainer {
                NavigationStack {
                    songLibraryPanel()
                        .navigationDestination(isPresented: songEditorDestination) {
                            songEditorDestinationContent(for: setlist)
                        }
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
            .onReceive(NotificationCenter.default.publisher(for: .outputRoutingDidChange)) { _ in
                coordinator.applyOutputRouting()
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
            .onChange(of: coordinator.currentSong?.dynamicCuesEnabled ?? false) { _, _ in
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
                showingSongLibrary = false
                songToEditID = nil
            }
            #if os(iOS)
            .onChange(of: showingSongLibrary) { _, isShowing in
                if !isShowing {
                    songToEditID = nil
                }
            }
            #endif
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
            #if os(macOS)
            .navigationDestination(isPresented: songEditorDestination) {
                songEditorDestinationContent(for: setlist)
            }
            #endif
    }

    private var playbackMainLayout: some View {
        #if os(macOS)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if placesTransportControlsAtBottom {
                LiveTransportBottomBar {
                    transportStrip(chrome: .portraitBottom)
                }
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
                if placesTransportControlsAtBottom {
                    LiveTransportBottomBar {
                        transportStrip(chrome: .portraitBottom)
                    }
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

    private func transportStrip(chrome: SharedTransportStripChrome) -> some View {
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
            onToggleFade: toggleGroupMixFade,
            chrome: chrome
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
                songToEditID = song.id
            },
            onDismiss: {
                showingSongLibrary = false
            },
            onFolderSelected: { folderURL in
                importSong(from: folderURL)
            },
            onAddToSetlist: { song in
                addSong(song, at: workingSetlist.sortedEntries.count)
            },
            isImportInProgress: isImportingSongFolder
        )
    }

    private func presentSongEditor(for song: Song) {
        #if os(iOS)
        showingSongLibrary = true
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
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            isLoaded: coordinator.isLoaded && !coordinator.isLoadingSong,
            canLoop: !loopSections.isEmpty,
            onStop: stopPlayback,
            onPlay: coordinator.play,
            onPause: coordinator.pause,
            onToggleLoop: toggleSectionLoop,
            onToggleFade: toggleGroupMixFade,
            showingSongLibrary: $showingSongLibrary,
            showingManageOutputs: $showingManageOutputs,
            mixerDetent: $mixerDetent,
            infoPanelHeight: $infoPanelHeight,
            transportChrome: placesTransportControlsAtBottom ? nil : .full
        )
    }

    private func importSong(from folderURL: URL) {
        guard !isImportingSongFolder else { return }

        isImportingSongFolder = true
        Task { @MainActor in
            defer { isImportingSongFolder = false }

            do {
                let importResult = try SongFolderImporter.importFromFolder(
                    at: folderURL,
                    context: modelContext
                )
                songImportFeedback = .success(SongFolderImporter.summaryMessage(for: importResult))
            } catch {
                songImportFeedback = .failure(error.localizedDescription)
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
            dynamicCuesEnabled: coordinator.currentSong?.dynamicCuesEnabled ?? false,
            sections: loopSections,
            announcer: sectionAnnouncer,
            sectionLoop: sectionLoop,
            loopSections: loopSections,
            loopSlotIDs: loopSlotIDs,
            playbackEngine: coordinator.playbackEngine,
            onLoopActivated: { clearMarkerCue() }
        )
    }

    private func prepareSectionAnnouncements() {
        guard coordinator.currentSong?.dynamicCuesEnabled == true else { return }
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
            "\(song.id.uuidString)|\(song.name)|\(song.tracks.count)|\(song.bpm ?? -1)|\(song.createdAt.timeIntervalSinceReferenceDate)"
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
        VStack(spacing: 0) {
            if setlistHasSongs {
                currentSongSection
                    .background(AppColors.backgroundPrimary)
            }

            setlistSection
                .background(AppColors.backgroundPrimary)
        }
    }

    private var currentSongSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let loadError = coordinator.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(AppSpacing.md)
            } else {
                LiveSetlistWaveformResizablePanel {
                    waveformContent
                        .padding(.top, AppSpacing.xs)
                }
            }
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
                }
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
                onAddHeader: addHeader,
                onAddSong: { showingSongLibrary = true }
            )

            Group {
                if workingSetlist.sortedEntries.isEmpty {
                    AppEmptyState(
                        title: "No Songs in Setlist",
                        systemImage: "music.note.list",
                        description: "Use the add button to build your setlist."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(AppSpacing.md)
                    .contentShape(Rectangle())
                    .contextMenu {
                        addHeaderContextMenu
                    }
                } else {
                    setlistList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var addHeaderContextMenu: some View {
        Button {
            addHeader()
        } label: {
            Label("Add Header", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
    }

    private var setlistList: some View {
        setlistEntryList
            .frame(maxWidth: 720, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
    }

    private var setlistEntryList: some View {
        List {
            Section {
                ForEach(Array(workingSetlist.sortedEntries.enumerated()), id: \.element.id) { _, entry in
                    if entry.isHeader {
                        setlistHeaderRow(entry: entry)
                    } else if let song = entry.song {
                        setlistEntryRow(song: song, entry: entry)
                    }
                }
                .onDelete { indexSet in
                    let entries = workingSetlist.sortedEntries
                    for index in indexSet {
                        viewModel.removeEntry(entries[index], from: workingSetlist, context: modelContext)
                    }
                    coordinator.syncSetlist(workingSetlist)
                }
                #if os(iOS)
                .onMove { source, destination in
                    viewModel.moveEntries(
                        in: workingSetlist,
                        from: source,
                        to: destination,
                        context: modelContext
                    )
                    coordinator.syncSetlist(workingSetlist)
                }
                #endif
            }
        }
        .liveSetlistListChrome()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        #if os(macOS)
        .onDrop(of: [.text], delegate: setlistDropDelegate(targetID: nil))
        #endif
        .contextMenu {
            addHeaderContextMenu
        }
        // Avoid GeometryReader+List: after compact→regular rotation on device the list
        // can keep a blank content area. Recreate when size class changes.
        #if os(iOS)
        .id(verticalSizeClass)
        #endif
    }

    private func setlistHeaderRow(entry: SetlistEntry) -> some View {
        let title = entry.headerTitle ?? ""

        return LiveSetlistHeaderRow(title: title)
            .liveSetlistTrailingReorderHandle(accessibilityNoun: "header") {
                commitSetlistReorder()
                draggedSetlistEntryID = entry.id
                return NSItemProvider(object: "setlist-entry" as NSString)
            }
            .liveSetlistHeaderRowChrome(isDragging: isBeingDragged(entry))
            #if os(macOS)
            .onDrop(of: [.text], delegate: setlistDropDelegate(targetID: entry.id))
            #endif
            #if os(iOS)
            .deleteDisabled(true)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Remove", role: .destructive) {
                    removeFromSetlist(entry)
                }
            }
            #endif
            .contextMenu {
                Button {
                    headerPendingEdit = entry
                    editHeaderTitle = entry.headerTitle ?? ""
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button("Remove from Setlist", role: .destructive) {
                    removeFromSetlist(entry)
                }
            }
    }

    private func setlistEntryRow(song: Song, entry: SetlistEntry) -> some View {
        let playbackIndex = workingSetlist.playbackIndex(for: entry) ?? 0
        let transition = workingSetlist.hasNextSong(after: entry) ? entry.transition : nil

        let selectSong = {
            coordinator.goToSong(at: playbackIndex, autoPlay: coordinator.isAudiblePlaying)
        }

        return LiveSetlistSongRow(
            song: song,
            duration: songTimelineDuration(for: song),
            index: playbackIndex,
            currentIndex: coordinator.currentIndex,
            hasMissingMedia: songHasMissingMedia(song),
            transition: transition,
            onOverlapBadgeTap: transition == .overlap
                ? { presentOverlapEditor(for: entry) }
                : nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectSong)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play", selectSong)
        .appLinkPointer()
        .liveSetlistTrailingReorderHandle(
            accessibilityNoun: "song",
            isCurrent: playbackIndex == coordinator.currentIndex
        ) {
            commitSetlistReorder()
            draggedSetlistEntryID = entry.id
            return NSItemProvider(object: "setlist-entry" as NSString)
        }
        .liveSetlistSongRowChrome(
            isDragging: isBeingDragged(entry),
            isCurrent: playbackIndex == coordinator.currentIndex
        )
        .mappableLiveControl(.goToSong(playbackIndex), cornerRadius: AppRadius.sm)
        #if os(macOS)
        .onDrop(of: [.text], delegate: setlistDropDelegate(targetID: entry.id))
        #endif
        #if os(iOS)
        .deleteDisabled(true)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove", role: .destructive) {
                removeFromSetlist(entry)
            }
        }
        #endif
        .contextMenu {
            Button {
                coordinator.goToSong(at: playbackIndex, autoPlay: coordinator.isAudiblePlaying)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            if transition != nil {
                Menu("Transition to Next") {
                    ForEach(availableTransitions(for: entry)) { option in
                        Button {
                            handleTransitionSelection(option, for: entry)
                        } label: {
                            Label(option.label, systemImage: option.systemImage)
                        }
                    }
                }
            }

            Button {
                presentSongEditor(for: song)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if songHasMissingMedia(song) {
                Button {
                    presentMissingMediaRelink(for: song)
                } label: {
                    Label("Relink Missing Files…", systemImage: "exclamationmark.triangle")
                }
            }

            Button("Remove from Setlist", role: .destructive) {
                removeFromSetlist(entry)
            }
        }
    }

    private func isBeingDragged(_ entry: SetlistEntry) -> Bool {
        draggedSetlistEntryID == entry.id
    }

    private func setlistDropDelegate(targetID: PersistentIdentifier?) -> LiveSetlistEntryDropDelegate<PersistentIdentifier> {
        LiveSetlistEntryDropDelegate(
            targetID: targetID,
            draggedID: draggedSetlistEntryID,
            onMove: previewSetlistMove,
            onCommit: commitSetlistReorder
        )
    }

    private func previewSetlistMove(_ draggedID: PersistentIdentifier, before targetID: PersistentIdentifier) {
        let entries = workingSetlist.sortedEntries
        guard let sourceIndex = entries.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = entries.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex else {
            return
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        hasPendingSetlistReorder = true
        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
            viewModel.previewMoveEntries(
                in: workingSetlist,
                from: IndexSet(integer: sourceIndex),
                to: destination
            )
        }
    }

    private func commitSetlistReorder() {
        let movedEntry = draggedSetlistEntryID.flatMap { id in
            workingSetlist.sortedEntries.first { $0.id == id }
        }
        draggedSetlistEntryID = nil

        guard hasPendingSetlistReorder else { return }
        hasPendingSetlistReorder = false

        viewModel.commitEntryOrder(
            in: workingSetlist,
            movedEntries: movedEntry.map { [$0] } ?? [],
            context: modelContext
        )
        coordinator.syncSetlist(workingSetlist)
    }

    private func songHasMissingMedia(_ song: Song) -> Bool {
        _ = mediaHealthRevision
        return SongMediaHealth.hasMissingMedia(song)
    }

    private func songTimelineDuration(for song: Song) -> TimeInterval {
        coordinator.waveformSnapshot(for: song)?.timelineDuration
            ?? TimecodePlaybackSupport.timelineDuration(for: song)
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
            headerPendingEdit = entry
            editHeaderTitle = entry.headerTitle ?? "New Header"
        }
    }

    private func saveHeaderEdit() {
        guard let entry = headerPendingEdit else { return }
        viewModel.renameHeader(entry, title: editHeaderTitle, context: modelContext)
        headerPendingEdit = nil
    }

    private var loopSlotIDs: Set<UUID> {
        coordinator.currentWaveformSnapshot?.loopSlotIDs ?? []
    }

    private var loopSections: [ArrangementDisplaySection] {
        coordinator.currentWaveformSnapshot?.sections ?? []
    }

    private var sectionAnnouncementTaskID: String {
        let songID = coordinator.currentSong?.id.uuidString ?? "none"
        let enabled = coordinator.currentSong?.dynamicCuesEnabled == true
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

    private func cueSection(_ section: ArrangementDisplaySection) {
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

    private func sectionCueFireTime(for cuedSection: ArrangementDisplaySection) -> TimeInterval {
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
        guard coordinator.currentTime >= cueFireTime else { return }
        guard let section = coordinator.currentWaveformSnapshot?.sections.first(where: { $0.id == cuedSectionID }) else {
            clearMarkerCue(cancellingScheduledTransition: false)
            return
        }
        coordinator.snapToScheduledSection(section.timelineStartSeconds)
        clearMarkerCue(cancellingScheduledTransition: false)
    }
}

private struct LivePlaybackMonitorSupport: View {
    let cuedSectionID: UUID?
    let cueFireTime: TimeInterval?
    let onFireMarkerCue: () -> Void
    let dynamicCuesEnabled: Bool
    let sections: [ArrangementDisplaySection]
    let announcer: SectionAnnouncer
    @Bindable var sectionLoop: SectionLoopController
    let loopSections: [ArrangementDisplaySection]
    let loopSlotIDs: Set<UUID>
    var playbackEngine: AudioEngineManager
    let onLoopActivated: () -> Void

    var body: some View {
        SectionCueMonitor(
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            onFire: onFireMarkerCue
        )
        SectionAnnounceMonitor(
            enabled: dynamicCuesEnabled,
            sections: sections,
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            announcer: announcer
        )
        SectionLoopPlaybackSupport(
            playbackEngine: playbackEngine,
            loopController: sectionLoop,
            sections: loopSections,
            loopSlotIDs: loopSlotIDs,
            onLoopActivated: onLoopActivated
        )
    }
}

private struct LiveSetlistToolbarContent<Switcher: View>: ToolbarContent {
    @ViewBuilder let setlistSwitcher: Switcher
    let coordinator: PlaybackCoordinator
    @Bindable var sectionLoop: SectionLoopController
    @Bindable var groupMixFade: GroupMixFadeController
    let isLoaded: Bool
    let canLoop: Bool
    let onStop: () -> Void
    let onPlay: () -> Void
    let onPause: () -> Void
    let onToggleLoop: () -> Void
    let onToggleFade: () -> Void
    @Binding var showingSongLibrary: Bool
    @Binding var showingManageOutputs: Bool
    @Binding var mixerDetent: LiveGroupMixerDetent
    @Binding var infoPanelHeight: CGFloat
    var transportChrome: SharedTransportStripChrome? = .full

    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            songsButton
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .principal) {
            transportInfoBar
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            InputMappingToolbarMenu()
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            mixerButton
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .primaryAction) {
            settingsButton
        }
        .cuesHideSharedBackground()
        #else
        ToolbarItem(placement: .topBarLeading) {
            setlistSwitcher
        }

        if let transportChrome {
            ToolbarItem(placement: .principal) {
                transportInfoBar(chrome: transportChrome)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            InputMappingToolbarMenu()
        }

        ToolbarItem(placement: .topBarTrailing) {
            mixerButton
        }

        ToolbarItem(placement: .topBarTrailing) {
            manageOutputsButton
        }
        #endif
    }

    #if os(macOS)
    private var transportInfoBar: some View {
        transportInfoBar(chrome: .full)
    }
    #endif

    private func transportInfoBar(chrome: SharedTransportStripChrome) -> some View {
        LiveSetlistNowPlayingInfoView(
            coordinator: coordinator,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            isLoaded: isLoaded,
            canLoop: canLoop,
            infoPanelHeight: $infoPanelHeight,
            onStop: onStop,
            onPlay: onPlay,
            onPause: onPause,
            onToggleLoop: onToggleLoop,
            onToggleFade: onToggleFade,
            chrome: chrome
        )
    }

    private var songsButton: some View {
        Button {
            showingSongLibrary.toggle()
        } label: {
            Label("Songs", systemImage: "music.note.list")
                .labelStyle(.iconOnly)
        }
        .tint(showingSongLibrary ? AppColors.accent : nil)
        .help("Songs")
    }

    #if os(macOS)
    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .help("Settings")
    }
    #else
    private var manageOutputsButton: some View {
        Button {
            showingManageOutputs = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .tint(showingManageOutputs ? AppColors.accent : nil)
        .help("Settings")
    }
    #endif

    private var mixerButton: some View {
        Button {
            #if os(macOS)
            mixerDetent = mixerDetent == .hidden ? .visible : .hidden
            #else
            mixerDetent = .visible
            #endif
        } label: {
            Label("Group Mixer", systemImage: "slider.vertical.3")
                .labelStyle(.iconOnly)
        }
        #if os(macOS)
        .tint(mixerDetent == .visible ? AppColors.accent : nil)
        #endif
        .help("Group Mixer")
    }
}

#if os(macOS)
private struct LivePlaybackMacToolbarBackgroundVisibilityModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}
#endif

private struct LiveRemoteHostSyncModifier: ViewModifier {
    let setlist: Setlist
    let librarySignature: String
    let coordinator: PlaybackCoordinator
    let sectionLoop: SectionLoopController
    let groupMixFade: GroupMixFadeController
    let cuedSectionID: UUID?
    let cueFireTime: TimeInterval?
    let remoteHostController: RemoteHostSessionController
    let isClientAuthenticated: Bool
    let sync: () -> Void

    private var setlistStructureSignature: String {
        setlist.sortedEntries.map { entry in
            let identity = entry.song?.id.uuidString ?? "header:\(entry.headerTitle ?? "")"
            return "\(entry.sortOrder)|\(identity)|\(entry.transition.rawValue)"
        }
        .joined(separator: ";")
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: sync)
            .onChange(of: setlist.id) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: setlist.entries.count) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: setlistStructureSignature) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: librarySignature) { _, _ in
                sync()
                remoteHostController.notifySnapshotChanged()
            }
            .onChange(of: coordinator.currentIndex) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: coordinator.isPlaying) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: sectionLoop.activeSectionID) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: sectionLoop.manualSectionID) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: groupMixFade.isFadedOut) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: groupMixFade.isFading) { _, _ in
                remoteHostController.notifyStateChanged()
            }
            .onChange(of: cuedSectionID) { _, newValue in
                remoteHostController.updateCue(cuedSectionID: newValue, cueFireTime: cueFireTime)
            }
            .onChange(of: cueFireTime) { _, newValue in
                remoteHostController.updateCue(cuedSectionID: cuedSectionID, cueFireTime: newValue)
            }
            .onChange(of: isClientAuthenticated) { _, connected in
                if connected {
                    remoteHostController.notifySnapshotChanged()
                }
            }
            .overlay(alignment: .top) {
                if isClientAuthenticated {
                    Text("Remote control connected")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.accent.opacity(0.85), in: Capsule())
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
    }
}

#Preview {
    NavigationStack {
        LivePlaybackView()
    }
    .modelContainer(for: [Setlist.self, SetlistEntry.self, Song.self], inMemory: true)
}
