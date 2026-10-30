import SwiftUI

struct RemoteLivePlaybackView: View {
    @Bindable private var client = RemoteSessionClientService.shared
    @Environment(InputMappingController.self) private var mapping
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var mixerVisible = false
    @State private var infoPanelHeight: CGFloat = 44
    @State private var cueFlashPhase = false
    @State private var showingSettings = false
    @State private var showingSongLibrary = false
    @State private var showingAddHeaderAlert = false
    @State private var isEditingSetlist = false
    @State private var newHeaderTitle = "New Header"
    @State private var newHeaderTimeText = "0:00"
    @State private var workingEntries: [RemoteSetlistEntryDTO] = []

    private var snapshot: RemoteSessionSnapshot? { client.snapshot }
    private var state: RemoteSessionState { client.state }
    private var librarySongs: [RemoteLibrarySongDTO] { snapshot?.librarySongs ?? [] }

    #if os(iOS)
    private var placesTransportControlsAtBottom: Bool {
        LiveTransportLayout.placesControlsAtBottom(
            verticalSizeClass: verticalSizeClass,
            horizontalSizeClass: horizontalSizeClass
        )
    }
    #else
    private var placesTransportControlsAtBottom: Bool { LiveTransportLayout.macOSPlacesControlsAtBottom }
    #endif

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

    private var transportStatus: TransportStatusSnapshot {
        TransportStatusSnapshot(
            position: state.positionText,
            bpm: state.bpmText,
            meter: state.meterText,
            key: state.keyText
        )
    }

    var body: some View {
        Group {
            #if os(macOS)
            LivePlaybackTrailingSidebarLayout(isVisible: mapping.isMapping) {
                InputMappingPanel()
            } mainContent: {
                LivePlaybackSidebarLayout(isVisible: $showingSongLibrary) {
                    remoteSongLibraryPanel
                } mainContent: {
                    remotePlaybackMain
                }
            }
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
                songsLibraryButton
            }
            .cuesHideSharedBackground()
            #endif

            if LiveTransportLayout.showsToolbarTransport(
                placesControlsAtBottom: placesTransportControlsAtBottom
            ) {
                ToolbarItem(placement: .principal) {
                    transportBar(chrome: .full)
                }
                #if os(macOS)
                .cuesHideSharedBackground()
                #endif
            }
            #if os(macOS)
            if !LiveTransportLayout.showsToolbarTransport(
                placesControlsAtBottom: placesTransportControlsAtBottom
            ) {
                ToolbarItem(placement: .principal) {
                    LiveToolbarSongTitle(
                        title: resolvedCurrentSong?.name ?? "",
                        upNext: song(atPlaybackIndex: state.currentIndex + 1)?.name
                    )
                }
                .cuesHideSharedBackground()
            }
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
        .toolbarBackground(AppColors.backgroundPrimary, for: .windowToolbar)
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
        .alert("New Header", isPresented: $showingAddHeaderAlert) {
            TextField("Header title", text: $newHeaderTitle)
            TextField("Time", text: $newHeaderTimeText)
            Button("Add") {
                addHeaderToSetlist()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Headers divide the setlist into sections. Time uses m:ss or h:mm:ss.")
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
            if snapshot != nil, !(snapshot?.entries.isEmpty ?? true) {
                VSplitView {
                    waveformSection
                    setlistSection
                }
            } else {
                waveformSection
                setlistSection
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
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if placesTransportControlsAtBottom {
                    LiveTransportBottomBar {
                        #if os(macOS)
                        transportBar(chrome: .full)
                        #else
                        transportBar(chrome: .portraitBottom)
                        #endif
                    }
                }
                #if os(macOS)
                if mixerVisible {
                    RemoteGroupMixerView(client: client)
                        .frame(height: 220)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                #endif
            }
        }
        #if os(macOS)
        .animation(AppAnimation.fadeQuick, value: mixerVisible)
        #endif
        .animation(AppAnimation.fadeQuick, value: placesTransportControlsAtBottom)
    }

    private var songsLibraryButton: some View {
        Button {
            showingSongLibrary.toggle()
        } label: {
            Label("Songs", systemImage: "music.note.list")
                .labelStyle(.iconOnly)
        }
        .tint(showingSongLibrary ? AppColors.accent : nil)
        .help("Songs")
    }

    private var remoteSongLibraryPanel: some View {
        RemoteHostSongLibraryPanel(
            songs: librarySongs,
            onDismiss: { showingSongLibrary = false },
            onAddToSetlist: { song in
                client.send(.addSongToSetlist(songID: song.id, atIndex: nil))
            }
        )
    }

    private func addHeaderToSetlist() {
        let trimmed = newHeaderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let timeSeconds = LiveSetlistDurationFormat.seconds(fromClock: newHeaderTimeText) ?? 0
        client.send(.addSetlistHeader(title: trimmed, atIndex: nil, timeSeconds: timeSeconds))
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
        }
    }

    private func transportBar(chrome: SharedTransportStripChrome) -> some View {
        SharedTransportStrip(
            snapshot: transportStatus,
            buttonSize: max(infoPanelHeight, 44),
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
            onReadoutHeightChange: { infoPanelHeight = $0 },
            chrome: chrome,
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
            onSelectSong: { index in
                client.send(.goToSong(
                    index: index,
                    autoPlay: state.isAudiblePlaying
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
                onAddHeader: {
                    newHeaderTitle = "New Header"
                    newHeaderTimeText = "0:00"
                    showingAddHeaderAlert = true
                },
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
                        Button {
                            newHeaderTitle = "New Header"
                            newHeaderTimeText = "0:00"
                            showingAddHeaderAlert = true
                        } label: {
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
                        onAddHeader: {
                            newHeaderTitle = "New Header"
                            newHeaderTimeText = "0:00"
                            showingAddHeaderAlert = true
                        }
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

#if os(iOS)
struct RemoteGroupMixerScreen: View {
    @Bindable var client: RemoteSessionClientService

    var body: some View {
        RemoteGroupMixerView(client: client)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground(.secondary)
            .navigationTitle("Group Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .locksInterfaceOrientations(.landscape)
    }
}
#endif

struct RemoteGroupMixerView: View {
    @Bindable var client: RemoteSessionClientService

    private let stripWidth: CGFloat = 96

    private var groups: [RemoteGroupDTO] {
        (client.snapshot?.groups ?? []).filter(\.isMixable)
    }

    var body: some View {
        GeometryReader { geometry in
            let stripHeight = max(140, geometry.size.height - AppSpacing.xs - AppSpacing.xxs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppSpacing.xxs) {
                    ForEach(groups) { group in
                        LiveGroupChannelStrip(
                            title: group.name,
                            titleColor: TrackGroupPalette.colors(forPaletteKey: group.paletteKey).body,
                            groupID: group.id,
                            volume: volumeBinding(for: group.id),
                            isMuted: muteBinding(for: group.id),
                            stripHeight: stripHeight,
                            stripWidth: stripWidth,
                            onLiveVolumeChange: { groupID, liveVolume in
                                client.send(.setGroupVolume(
                                    groupID: groupID,
                                    volume: liveVolume,
                                    provisional: true
                                ))
                            },
                            // Commit happens via the volume binding setter on drag end.
                            onMixChange: {}
                        )
                    }

                    LiveGroupChannelStrip(
                        title: "No Group",
                        titleColor: TrackGroupPalette.colors(forPaletteKey: nil).body,
                        groupID: nil,
                        volume: Binding(
                            get: { client.state.ungroupedVolume },
                            set: { newValue in
                                client.send(.setGroupVolume(groupID: nil, volume: newValue, provisional: false))
                            }
                        ),
                        isMuted: Binding(
                            get: { client.state.ungroupedIsMuted },
                            set: { newValue in
                                client.send(.setGroupMuted(groupID: nil, muted: newValue))
                            }
                        ),
                        stripHeight: stripHeight,
                        stripWidth: stripWidth,
                        onLiveVolumeChange: { _, liveVolume in
                            client.send(.setGroupVolume(groupID: nil, volume: liveVolume, provisional: true))
                        },
                        // Commit happens via the volume binding setter on drag end.
                        onMixChange: {}
                    )
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xxs)
            }
        }
        .background(AppColors.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 0.5)
        }
    }

    private func volumeBinding(for groupID: UUID) -> Binding<Double> {
        Binding(
            get: {
                client.state.groupVolumes[groupID.uuidString]
                    ?? client.snapshot?.groups.first(where: { $0.id == groupID })?.volume
                    ?? 1
            },
            set: { newValue in
                client.send(.setGroupVolume(groupID: groupID, volume: newValue, provisional: false))
            }
        )
    }

    private func muteBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { client.state.mutedGroupIDs.contains(groupID) },
            set: { newValue in
                client.send(.setGroupMuted(groupID: groupID, muted: newValue))
            }
        )
    }
}

private enum RemoteHostSongLibrarySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case name = "Name"

    var id: String { rawValue }
}

/// Browse-only host song library for remote clients (add to setlist; no local media edits).
private struct RemoteHostSongLibraryPanel: View {
    let songs: [RemoteLibrarySongDTO]
    var onDismiss: () -> Void
    var onAddToSetlist: (RemoteLibrarySongDTO) -> Void

    @State private var searchText = ""
    @State private var sortOrder: RemoteHostSongLibrarySortOrder = .newest

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredSongs: [RemoteLibrarySongDTO] {
        var result = songs

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        switch sortOrder {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            headerBar
            #endif
            searchBar
            songList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.backgroundSecondary)
        #if os(iOS)
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button(role: .close) {
                        onDismiss()
                    }
                } else {
                    Button("Close") {
                        onDismiss()
                    }
                }
            }
        }
        #endif
    }

    private var headerBar: some View {
        Text("Songs")
            .appLargeTitle()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xs)
    }

    private var searchBar: some View {
        HStack(spacing: AppSpacing.xs) {
            AppSearchField(text: $searchText)

            if hasActiveSearch {
                Button("Clear") {
                    searchText = ""
                }
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .buttonStyle(.plain)
            }

            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(RemoteHostSongLibrarySortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(AppColors.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Sort songs")
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
    }

    @ViewBuilder
    private var songList: some View {
        if songs.isEmpty {
            AppEmptyState(
                title: "No Songs on Host",
                systemImage: "music.note",
                description: "The host song library is empty."
            )
            .padding(.top, AppSpacing.sm)
            Spacer(minLength: 0)
        } else if filteredSongs.isEmpty {
            AppEmptyState(
                title: "No Results",
                systemImage: "magnifyingglass",
                description: "No songs match \"\(searchText)\"."
            )
            .padding(.top, AppSpacing.sm)
            Spacer(minLength: 0)
        } else {
            List {
                ForEach(filteredSongs) { song in
                    RemoteHostSongLibraryRow(
                        song: song,
                        onAddToSetlist: { onAddToSetlist(song) }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button {
                            onAddToSetlist(song)
                        } label: {
                            Label("Add to Setlist", systemImage: "plus")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(AppColors.separator)
        }
    }
}

private struct RemoteHostSongLibraryRow: View {
    let song: RemoteLibrarySongDTO
    let onAddToSetlist: () -> Void

    private var subtitle: String {
        let trackText = song.trackCount == 0 ? "No tracks" : "\(song.trackCount) tracks"
        if let bpm = song.bpm {
            return "\(Int(bpm.rounded())) bpm — \(trackText)"
        }
        return trackText
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Button(action: onAddToSetlist) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appLinkPointer()
            .accessibilityLabel("Add to setlist")
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 0.5)
        }
    }
}
