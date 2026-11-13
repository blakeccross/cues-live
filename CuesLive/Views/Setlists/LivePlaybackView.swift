import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MissingMediaSheetContext: Identifiable {
    let id = UUID()
    let setlistID: UUID
    let focusedSongID: UUID?
    let missingTracks: [SongMediaHealth.MissingTrack]
}

struct LivePlaybackView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(InputMappingController.self) private var mapping
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Query(sort: \Song.name) var allSongs: [Song]
    @Query(sort: \Setlist.lastOpenedAt, order: .reverse) private var allSetlists: [Setlist]

    @State var activeSetlistID: UUID?
    @State private var didBootstrap = false
    @State var coordinator = PlaybackCoordinator()
    @State var viewModel = SetlistViewModel()
    @Bindable var playbackClock = AudioEngineManager.shared
    @State var cuedSectionID: UUID?
    @State var cueFireTime: TimeInterval?
    @State var cueFlashPhase = false
    @State var sectionLoop = SectionLoopController()
    @State var groupMixFade = GroupMixFadeController()
    @State var sectionAnnouncer = SectionAnnouncer()
    @State var showingSongLibrary = SongSidebarPreference.initialVisibility
    @State private var songToEditID: UUID?
    /// Song to open once the library sheet has dismissed, so the editor pushes as a screen.
    @State private var songPendingEditorID: UUID?
    @State private var showingManageOutputs = false
    @State var showingShowFileImporter = false
    @State var showingSetlistPackageExporter = false
    @State var setlistPackageDocument: SetlistPackageFileDocument?
    @State var showingShowFileExporter = false
    @State var showFileDocument: ShowFileDocument?
    @State var songImportFeedback: SongImportFeedback?
    @State var isImportingSongFolder = false
    @State var mixerDetent: LiveGroupMixerDetent = .hidden
    @State var headerPendingEdit: SetlistEntry?
    @State var isCreatingHeader = false
    @State var isEditingSetlist = false
    @State var editHeaderTitle = ""
    @State var editHeaderTimeSeconds: TimeInterval = 0
    @State var overlapEditorContext: SetlistOverlapEditorContext?
    @State var setlistRowMetrics = SetlistRowMetricsCache()
    @State private var showingMissingMediaAlert = false
    @State private var missingMediaSheet: MissingMediaSheetContext?
    @State var ignoredMissingMediaPromptForSetlistID: UUID?
    @State var mediaHealthRevision = 0
    @Bindable private var remoteHost = RemoteSessionHostService.shared
    private var remoteHostController: RemoteHostSessionController { .shared }

    var activeSetlist: Setlist? {
        if let activeSetlistID,
           let setlist = allSetlists.first(where: { $0.id == activeSetlistID }) {
            return setlist
        }
        return allSetlists.first
    }

    /// Prefer `activeSetlist` in outer body modifiers; SwiftUI may evaluate them before bootstrap.
    var workingSetlist: Setlist {
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
            .onChange(of: coordinator.currentSong?.id) { _, songID in
                SetlistEditorLink.shared.activeSongDidChange(to: songID)
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
                SetlistEditorLink.shared.attach(coordinator)
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
                SetlistEditorLink.shared.detach(coordinator)
            }
            .onChange(of: songToEditID) { oldValue, newValue in
                SetlistEditorLink.shared.setInlineEditorOpen(newValue != nil)
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

    func presentSongEditor(for song: Song) {
        #if os(macOS)
        // An open editor window takes the song, so the setlist keeps playing here.
        if SetlistEditorLink.shared.isWindowOpen {
            SetlistEditorLink.shared.edit(song.id)
            openWindow(id: SetlistSongEditorWindowID.value)
            return
        }
        #endif
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

    func switchToSetlist(_ setlist: Setlist) {
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

    func promptForMissingMediaIfNeeded(in setlist: Setlist) {
        mediaHealthRevision += 1
        let missing = SongMediaHealth.missingTracks(in: setlist)
        guard !missing.isEmpty else { return }
        guard ignoredMissingMediaPromptForSetlistID != setlist.id else { return }
        showingMissingMediaAlert = true
    }

    func presentMissingMediaRelink(for song: Song? = nil) {
        guard let setlist = activeSetlist else { return }
        let missing = SongMediaHealth.missingTracks(in: setlist)
        missingMediaSheet = MissingMediaSheetContext(
            setlistID: setlist.id,
            focusedSongID: song?.id,
            missingTracks: missing
        )
    }

    func markSetlistOpened(_ setlist: Setlist) {
        setlist.lastOpenedAt = Date()
        try? modelContext.save()
    }

    func stopPlayback() {
        clearMarkerCue()
        sectionLoop.reset()
        groupMixFade.clearFade(context: modelContext) {
            coordinator.updateGroupMix(context: modelContext)
        }
        coordinator.stop()
    }

    struct LiveSetlistWaveformLoadingPlaceholder: View {
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
}
#Preview {
    NavigationStack {
        LivePlaybackView()
    }
    .modelContainer(for: [Setlist.self, SetlistEntry.self, Song.self], inMemory: true)
}
