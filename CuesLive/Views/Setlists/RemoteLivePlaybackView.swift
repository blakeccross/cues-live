import SwiftUI
import UniformTypeIdentifiers

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
    @State private var newHeaderTitle = "New Header"
    @State private var workingEntries: [RemoteSetlistEntryDTO] = []
    @State private var draggedSetlistEntryID: UUID?
    @State private var hasPendingSetlistReorder = false

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
    private var placesTransportControlsAtBottom: Bool { false }
    #endif

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
            ToolbarItem(placement: .primaryAction) {
                InputMappingToolbarMenu()
            }
            #if os(macOS)
            .cuesHideSharedBackground()
            #endif

            ToolbarItem(placement: .primaryAction) {
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

            ToolbarItem(placement: .primaryAction) {
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
            Button("Add") {
                addHeaderToSetlist()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Headers divide the setlist into sections.")
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

            waveformSection
            setlistSection
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
                        transportBar(chrome: .portraitBottom)
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
        client.send(.addSetlistHeader(title: trimmed, atIndex: nil))
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
    private var waveformSection: some View {
        if let snapshot, !snapshot.entries.isEmpty {
            LiveSetlistWaveformResizablePanel {
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
                onAddHeader: {
                    newHeaderTitle = "New Header"
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
                    List {
                        Section {
                            ForEach(workingEntries) { entry in
                                remoteSetlistRow(entry: entry, snapshot: snapshot)
                            }
                            .onDelete(perform: deleteWorkingEntries)
                            #if os(iOS)
                            .onMove(perform: moveWorkingEntries)
                            #endif
                        }
                    }
                    .liveSetlistListChrome()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .onDrop(of: [.text], delegate: remoteSetlistDropDelegate(targetID: nil))
                    #endif
                    .contextMenu {
                        Button {
                            newHeaderTitle = "New Header"
                            showingAddHeaderAlert = true
                        } label: {
                            Label("Add Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                    }
                    // Avoid GeometryReader+List: after compact→regular rotation on device the
                    // list can keep a blank content area. Recreate when size class changes.
                    #if os(iOS)
                    .id(verticalSizeClass)
                    #endif
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
            guard !hasPendingSetlistReorder, draggedSetlistEntryID == nil else { return }
            syncWorkingEntries(from: newEntries ?? [])
        }
    }

    @ViewBuilder
    private func remoteSetlistRow(
        entry: RemoteSetlistEntryDTO,
        snapshot: RemoteSessionSnapshot
    ) -> some View {
        if let header = entry.headerTitle, entry.songID == nil {
            LiveSetlistHeaderRow(title: header)
                .liveSetlistTrailingReorderHandle(accessibilityNoun: "header") {
                    commitRemoteSetlistReorder()
                    draggedSetlistEntryID = entry.id
                    return NSItemProvider(object: "setlist-entry" as NSString)
                }
                .liveSetlistHeaderRowChrome(isDragging: isBeingDragged(entry))
                #if os(macOS)
                .onDrop(of: [.text], delegate: remoteSetlistDropDelegate(targetID: entry.id))
                #endif
                #if os(iOS)
                .deleteDisabled(true)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Remove", role: .destructive) {
                        removeWorkingEntry(entry)
                    }
                }
                #endif
                .contextMenu {
                    Button("Remove from Setlist", role: .destructive) {
                        removeWorkingEntry(entry)
                    }
                }
        } else if let songID = entry.songID,
                  let song = snapshot.songs.first(where: { $0.id == songID }),
                  let playbackIndex = entry.playbackIndex {
            let transition = remoteTransition(for: entry, in: workingEntries)
            let selectSong = {
                client.send(.goToSong(
                    index: playbackIndex,
                    autoPlay: state.isAudiblePlaying
                ))
            }

            LiveSetlistSongRow(
                title: song.name,
                durationText: LiveSetlistDurationFormat.clock(for: song.timelineDuration),
                index: playbackIndex,
                currentIndex: state.currentIndex,
                keyText: remoteSongKeyText(song),
                bpmText: remoteSongBPMText(song),
                transition: transition
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: selectSong)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Play", selectSong)
            .appLinkPointer()
            .liveSetlistTrailingReorderHandle(
                accessibilityNoun: "song",
                isCurrent: playbackIndex == state.currentIndex
            ) {
                commitRemoteSetlistReorder()
                draggedSetlistEntryID = entry.id
                return NSItemProvider(object: "setlist-entry" as NSString)
            }
            .liveSetlistSongRowChrome(
                isDragging: isBeingDragged(entry),
                isCurrent: playbackIndex == state.currentIndex
            )
            .mappableLiveControl(.goToSong(playbackIndex), cornerRadius: AppRadius.sm)
            #if os(macOS)
            .onDrop(of: [.text], delegate: remoteSetlistDropDelegate(targetID: entry.id))
            #endif
            #if os(iOS)
            .deleteDisabled(true)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Remove", role: .destructive) {
                    removeWorkingEntry(entry)
                }
            }
            #endif
            .contextMenu {
                Button {
                    client.send(.goToSong(
                        index: playbackIndex,
                        autoPlay: state.isAudiblePlaying
                    ))
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                Button("Remove from Setlist", role: .destructive) {
                    removeWorkingEntry(entry)
                }
            }
        }
    }

    private func isBeingDragged(_ entry: RemoteSetlistEntryDTO) -> Bool {
        draggedSetlistEntryID == entry.id
    }

    private func remoteSetlistDropDelegate(targetID: UUID?) -> LiveSetlistEntryDropDelegate<UUID> {
        LiveSetlistEntryDropDelegate(
            targetID: targetID,
            draggedID: draggedSetlistEntryID,
            onMove: previewRemoteSetlistMove,
            onCommit: commitRemoteSetlistReorder
        )
    }

    private func previewRemoteSetlistMove(_ draggedID: UUID, before targetID: UUID) {
        guard let sourceIndex = workingEntries.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = workingEntries.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex else {
            return
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        hasPendingSetlistReorder = true
        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
            workingEntries.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
            recomputeWorkingEntryIndices()
        }
    }

    private func commitRemoteSetlistReorder() {
        let movedID = draggedSetlistEntryID
        draggedSetlistEntryID = nil

        guard hasPendingSetlistReorder else { return }
        hasPendingSetlistReorder = false

        guard let movedID,
              let toIndex = workingEntries.firstIndex(where: { $0.id == movedID }) else {
            return
        }
        client.send(.moveSetlistEntry(entryID: movedID, toIndex: toIndex))
    }

    private func deleteWorkingEntries(at offsets: IndexSet) {
        let entries = offsets.map { workingEntries[$0] }
        for entry in entries {
            removeWorkingEntry(entry)
        }
    }

    private func moveWorkingEntries(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        let movedID = workingEntries[sourceIndex].id
        workingEntries.move(fromOffsets: source, toOffset: destination)
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
            HStack(spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(AppColors.surface)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }

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
            }

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
