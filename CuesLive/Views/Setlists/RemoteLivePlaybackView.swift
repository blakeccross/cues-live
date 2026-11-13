import SwiftUI

struct RemoteLivePlaybackView: View {
    @Bindable private var client = RemoteSessionClientService.shared
    @Environment(InputMappingController.self) private var mapping

    @State private var mixerVisible = false
    @State private var cueFlashPhase = false
    @State private var showingSettings = false
    @State private var showingSongLibrary = SongLibraryPanePreference.initialVisibility
    @State private var showingAddHeaderSheet = false
    @State private var isEditingSetlist = false
    @State private var newHeaderTitle = "New Header"
    @State private var newHeaderTimeSeconds: TimeInterval = 0
    @State private var workingEntries: [RemoteSetlistEntryDTO] = []

    private var snapshot: RemoteSessionSnapshot? { client.snapshot }
    private var state: RemoteSessionState { client.state }
    private var librarySongs: [RemoteLibrarySongDTO] { snapshot?.librarySongs ?? [] }

    /// macOS `.primaryAction` is the leading edge, so these controls use `.automatic`.
    private var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .primaryAction
        #endif
    }

    private var resolvedCurrentSong: RemoteSongDTO? {
        guard let snapshot else { return nil }
        if let id = state.currentSongID,
           let song = snapshot.songs.first(where: { $0.id == id }) {
            return song
        }
        return song(atPlaybackIndex: state.currentIndex)
    }

    private var canLoop: Bool {
        let song = resolvedCurrentSong
        return !(song?.sections.isEmpty ?? true) || state.isLooping
    }

    var body: some View {
        Group {
            #if os(macOS)
            LivePlaybackTrailingSidebarLayout(isVisible: mapping.isMapping) {
                InputMappingPanel()
            } mainContent: {
                remotePlaybackMain
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            #else
            remotePlaybackMain
            #endif
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                SongLibraryToggleButton(isVisible: $showingSongLibrary)
            }
            .cuesHideSharedBackground()

            ToolbarItem(placement: .principal) {
                LiveToolbarSongTitle(
                    title: resolvedCurrentSong?.name ?? "",
                    upNext: song(atPlaybackIndex: state.currentIndex + 1)?.name
                )
            }
            .cuesHideSharedBackground()
            #endif
            ToolbarItem(placement: trailingToolbarPlacement) {
                InputMappingToolbarMenu()
            }
            #if os(macOS)
            .cuesHideSharedBackground()
            #endif

            ToolbarItem(placement: trailingToolbarPlacement) {
                Button {
                    #if os(macOS)
                    mixerVisible.toggle()
                    #else
                    mixerVisible = true
                    #endif
                } label: {
                    Label("Group Mixer", systemImage: "slider.vertical.3")
                        .labelStyle(.iconOnly)
                }
                #if os(macOS)
                .tint(mixerVisible ? AppColors.accent : nil)
                #endif
            }
            #if os(macOS)
            .cuesHideSharedBackground()
            #endif

            ToolbarItem(placement: trailingToolbarPlacement) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
            }
            #if os(macOS)
            .cuesHideSharedBackground()
            #endif
        }
        #if os(macOS)
        .appLockToolbarDisplayMode()
        #endif
        .appBackground(.primary)
        .liveInputMappingSession { action in
            handleMappedLiveAction(action)
        }
        .task(id: state.cuedSectionID) {
            guard state.cuedSectionID != nil else {
                cueFlashPhase = false
                return
            }
            while !Task.isCancelled, client.state.cuedSectionID != nil {
                cueFlashPhase.toggle()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        .sheet(isPresented: $showingSettings) {
            #if os(iOS)
            DeviceSettingsSheet()
            #else
            NavigationStack {
                List {
                    NavigationLink("Remote Session") {
                        RemoteSessionSettingsView()
                            .navigationTitle("Remote Session")
                    }
                    NavigationLink("Mappings") {
                        InputMappingSettingsView()
                            .navigationTitle("Mappings")
                    }
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingSettings = false }
                    }
                }
            }
            .standardDialogToolbar()
            .frame(minWidth: 480, minHeight: 420)
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingSongLibrary) {
            AppSheetContainer {
                NavigationStack {
                    remoteSongLibraryPanel
                }
            }
            .presentationDetents([.large])
        }
        #endif
        .sheet(isPresented: $showingAddHeaderSheet) {
            SetlistHeaderEditorSheet(
                navigationTitle: "New Header",
                confirmTitle: "Add",
                headerTitle: $newHeaderTitle,
                timeSeconds: $newHeaderTimeSeconds,
                onCancel: { showingAddHeaderSheet = false },
                onConfirm: {
                    addHeaderToSetlist()
                    showingAddHeaderSheet = false
                }
            )
        }
    }

    private var remotePlaybackMain: some View {
        VStack(spacing: 0) {
            if let loadError = state.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(AppSpacing.md)
            }

            #if os(macOS)
            Group {
                if snapshot != nil, !(snapshot?.entries.isEmpty ?? true) {
                    VSplitView {
                        waveformSection
                        librarySplitSection
                    }
                } else {
                    VStack(spacing: 0) {
                        waveformSection
                        librarySplitSection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if mixerVisible {
                RemoteGroupMixerView(client: client)
                    .frame(height: 220)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            LiveTransportBottomBar {
                transportBar
            }
            #else
            waveformSection
            setlistSection
            #endif
        }
        #if os(iOS)
        .navigationDestination(isPresented: $mixerVisible) {
            RemoteGroupMixerScreen(client: client)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LiveTransportBottomBar {
                transportBar
            }
        }
        #endif
        #if os(macOS)
        .animation(AppAnimation.fadeQuick, value: mixerVisible)
        #endif
    }

    #if os(macOS)
    private var librarySplitSection: some View {
        LiveSongLibrarySplitLayout(isLibraryVisible: showingSongLibrary) {
            remoteSongLibraryPanel
        } setlist: {
            setlistSection
        }
    }
    #endif

    private var remoteSongLibraryPanel: some View {
        RemoteHostSongLibraryPanel(
            songs: librarySongs,
            onDismiss: { showingSongLibrary = false },
            onAddToSetlist: { song in
                client.send(.addSongToSetlist(songID: song.id, atIndex: nil))
            }
        )
    }

    private func beginAddingHeader() {
        newHeaderTitle = "New Header"
        newHeaderTimeSeconds = 0
        showingAddHeaderSheet = true
    }

    private func addHeaderToSetlist() {
        let trimmed = newHeaderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        client.send(.addSetlistHeader(title: trimmed, atIndex: nil, timeSeconds: newHeaderTimeSeconds))
    }

    private func handleMappedLiveAction(_ action: MappableLiveAction) {
        switch action {
        case .stop:
            client.send(.stop)
        case .playPause:
            if state.isPlaying {
                client.send(.pause)
            } else {
                client.send(.play)
            }
        case .fade:
            client.send(.toggleFade)
        case .loop:
            client.send(.toggleSectionLoop)
        case .goToSong(let index):
            client.send(.goToSong(index: index, autoPlay: state.isAudiblePlaying))
        case .goToSection(let songIndex, let sectionIndex):
            performMappedSection(songIndex: songIndex, sectionIndex: sectionIndex)
        }
    }

    private func performMappedSection(songIndex: Int, sectionIndex: Int) {
        guard let song = song(atPlaybackIndex: songIndex),
              song.sections.indices.contains(sectionIndex) else { return }
        let section = song.sections[sectionIndex]
        if songIndex == state.currentIndex {
            client.send(.cueSection(sectionID: section.id))
            return
        }
        client.send(.goToSong(
            index: songIndex,
            autoPlay: state.isAudiblePlaying,
            startTime: section.timelineStartSeconds
        ))
    }

    private var transportBar: some View {
        SharedTransportStrip(
            buttonSize: 44,
            isPlaying: state.isPlaying,
            isLoaded: true,
            isLooping: state.isLooping,
            canLoop: canLoop,
            onStop: { client.send(.stop) },
            onPlay: { client.send(.play) },
            onPause: { client.send(.pause) },
            onToggleLoop: { client.send(.toggleSectionLoop) },
            isFadedOut: state.isFadedOut,
            isFading: state.isFading,
            onToggleFade: { client.send(.toggleFade) },
            enablesInputMapping: true
        )
    }

    @ViewBuilder
    private func timelineScrollView(for snapshot: RemoteSessionSnapshot) -> some View {
        LiveSetlistWaveformScrollView(
            timelineItems: snapshot.timelineItems,
            currentPlaybackIndex: state.currentIndex,
            waveformSnapshotForSongID: { snapshot.waveformSnapshot(forSongID: $0) },
            ensureWaveformSnapshotForSongID: { _ in },
            playheadTimeProvider: { client.state.currentTime },
            isPlayingProvider: { client.state.isPlaying },
            idlePlayheadTime: state.isPlaying ? nil : state.currentTime,
            cuedSectionID: state.cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            onSeek: { client.send(.seek($0)) },
            onCueSection: { client.send(.cueSection(sectionID: $0.id)) },
            onSelectSong: { index, startTime in
                client.send(.goToSong(
                    index: index,
                    autoPlay: state.isAudiblePlaying,
                    startTime: startTime
                ))
            }
        )
        .padding(.top, AppSpacing.xs)
    }

    @ViewBuilder
    private var waveformSection: some View {
        if let snapshot, !snapshot.entries.isEmpty {
            #if os(macOS)
            LiveSetlistWaveformResizablePane {
                timelineScrollView(for: snapshot)
            }
            #else
            timelineScrollView(for: snapshot)
            #endif
        } else {
            ContentUnavailableView(
                "Waiting for setlist",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("Connected to the host. Waiting for session data.")
            )
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var setlistSection: some View {
        VStack(spacing: 0) {
            LiveSetlistAddMenu(
                isEditing: workingEntries.isEmpty ? nil : $isEditingSetlist,
                onAddHeader: beginAddingHeader,
                onAddSong: { showingSongLibrary = true }
            )

            if snapshot != nil {
                if workingEntries.isEmpty {
                    AppEmptyState(
                        title: "No Songs in Setlist",
                        systemImage: "music.note.list",
                        description: "Use the add button or Songs library to build the setlist."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(AppSpacing.md)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(action: beginAddingHeader) {
                            Label("Add Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Button {
                            showingSongLibrary = true
                        } label: {
                            Label("Add Song", systemImage: "music.note")
                        }
                    }
                } else if let snapshot {
                    SetlistListView(
                        rows: remoteRowModels(snapshot: snapshot),
                        currentIndex: state.currentIndex,
                        isPlaying: state.isAudiblePlaying,
                        isEditing: $isEditingSetlist,
                        actions: remoteRowActions(for:),
                        onMove: moveWorkingEntries,
                        onAddHeader: beginAddingHeader
                    )
                    .frame(maxWidth: 720, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
        .onAppear {
            syncWorkingEntries(from: snapshot?.entries ?? [])
        }
        .onChange(of: snapshot?.entries) { _, newEntries in
            syncWorkingEntries(from: newEntries ?? [])
        }
        .onChange(of: workingEntries.isEmpty) { _, isEmpty in
            if isEmpty { isEditingSetlist = false }
        }
    }

    private func remoteRowModels(snapshot: RemoteSessionSnapshot) -> [SetlistRowModel] {
        workingEntries.compactMap { entry in
            if let header = entry.headerTitle, entry.songID == nil {
                let seconds = entry.headerTimeSeconds ?? 0
                return SetlistRowModel(
                    id: entry.id,
                    kind: .header(
                        title: header,
                        timeText: seconds > 0 ? LiveSetlistDurationFormat.clock(for: seconds) : nil
                    )
                )
            }
            guard let songID = entry.songID,
                  let song = snapshot.songs.first(where: { $0.id == songID }),
                  let playbackIndex = entry.playbackIndex else {
                return nil
            }
            return SetlistRowModel(
                id: entry.id,
                kind: .song(SetlistRowModel.Song(
                    title: song.name,
                    durationText: LiveSetlistDurationFormat.clock(for: song.timelineDuration),
                    keyText: remoteSongKeyText(song),
                    bpmText: remoteSongBPMText(song),
                    playbackIndex: playbackIndex,
                    hasSmartGuide: song.smartGuideEnabled,
                    transition: remoteTransition(for: entry, in: workingEntries)
                ))
            )
        }
    }

    /// The host protocol only supports play / move / remove, so the remote menu is smaller.
    private func remoteRowActions(for model: SetlistRowModel) -> SetlistRowActions {
        guard let entry = workingEntries.first(where: { AnyHashable($0.id) == model.id }) else {
            return SetlistRowActions(remove: {})
        }
        guard case .song(let song) = model.kind else {
            return SetlistRowActions(remove: { removeWorkingEntry(entry) })
        }
        return SetlistRowActions(
            play: {
                client.send(.goToSong(index: song.playbackIndex, autoPlay: state.isAudiblePlaying))
            },
            remove: { removeWorkingEntry(entry) }
        )
    }

    /// Rows skip entries whose song is missing from the snapshot, so translate row offsets
    /// into offsets in `workingEntries`.
    private func moveWorkingEntries(from source: IndexSet, to destination: Int) {
        guard let snapshot else { return }
        let visibleIDs = remoteRowModels(snapshot: snapshot).compactMap { $0.id.base as? UUID }
        guard let visibleSource = source.first, visibleSource < visibleIDs.count,
              let sourceIndex = workingEntries.firstIndex(where: { $0.id == visibleIDs[visibleSource] }) else {
            return
        }
        let destinationIndex = destination < visibleIDs.count
            ? (workingEntries.firstIndex(where: { $0.id == visibleIDs[destination] }) ?? workingEntries.count)
            : workingEntries.count
        let movedID = workingEntries[sourceIndex].id
        workingEntries.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destinationIndex)
        recomputeWorkingEntryIndices()
        guard let toIndex = workingEntries.firstIndex(where: { $0.id == movedID }) else { return }
        client.send(.moveSetlistEntry(entryID: movedID, toIndex: toIndex))
    }

    private func removeWorkingEntry(_ entry: RemoteSetlistEntryDTO) {
        workingEntries.removeAll { $0.id == entry.id }
        recomputeWorkingEntryIndices()
        client.send(.removeSetlistEntry(entryID: entry.id))
    }

    private func syncWorkingEntries(from entries: [RemoteSetlistEntryDTO]) {
        workingEntries = entries
    }

    private func recomputeWorkingEntryIndices() {
        var playbackIndex = 0
        for index in workingEntries.indices {
            workingEntries[index].sortOrder = index
            if workingEntries[index].songID != nil {
                workingEntries[index].playbackIndex = playbackIndex
                playbackIndex += 1
            } else {
                workingEntries[index].playbackIndex = nil
            }
        }
    }

    private func remoteSongBPMText(_ song: RemoteSongDTO) -> String? {
        guard let bpm = song.tempoChanges.first?.bpm else { return nil }
        return String(format: "%.0f BPM", bpm.rounded())
    }

    private func remoteSongKeyText(_ song: RemoteSongDTO) -> String? {
        let trimmed = song.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—", trimmed != "-" else { return nil }
        return trimmed
    }

    private func remoteTransition(
        for entry: RemoteSetlistEntryDTO,
        in entries: [RemoteSetlistEntryDTO]
    ) -> SetlistTransition? {
        guard entry.playbackIndex != nil else { return nil }
        let songEntries = entries.filter { $0.playbackIndex != nil }
        guard let index = songEntries.firstIndex(where: { $0.id == entry.id }),
              index < songEntries.count - 1 else {
            return nil
        }
        return SetlistTransition(rawValue: entry.transition)
    }

    private func song(atPlaybackIndex index: Int) -> RemoteSongDTO? {
        guard let snapshot,
              let entry = snapshot.entries.first(where: { $0.playbackIndex == index }),
              let songID = entry.songID else {
            return nil
        }
        return snapshot.songs.first { $0.id == songID }
    }
}
