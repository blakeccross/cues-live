import SwiftData
import SwiftUI

private enum SongLibrarySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case name = "Name"

    var id: String { rawValue }
}

/// The song library: search, sort, multi-select, and add or delete songs.
/// Selection follows platform conventions: ⌘/⇧-click on macOS, Select mode on iOS.
@MainActor
struct SongLibraryPanel: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Song.createdAt, order: .reverse) var songs: [Song]
    @Query var folders: [SongFolder]

    var scope: SongLibraryScope = .allSongs

    var onEdit: (Song) -> Void
    var onDismiss: () -> Void
    var onFoldersSelected: ([SongFolderImporter.ImportRequest]) -> Void
    var onAddToSetlist: (Song) -> Void
    var isImportInProgress = false

    @State private var searchText = ""
    @State private var sortOrder: SongLibrarySortOrder = .newest
    @State var selection: Set<UUID> = []
    #if os(iOS)
    @State var editMode: EditMode = .inactive
    #endif
    @State var showingAddClickSheet = false
    @State var folderSetupSession: SongFolderSetupSession?
    @State var isPreparingFolderSetup = false
    @State var songPendingRename: Song?
    @State var renameSongName = ""
    @State var songsPendingDelete: [Song] = []
    @State var createSongError: String?
    @State var songActionError: String?
    #if os(macOS)
    @State var isTargetedForFolderDrop = false
    #else
    @State var showingFolderImporter = false
    #endif
    @State var consolidateSummary: String?
    /// Bumps when a newer import should cancel an in-flight scroll-into-view.
    @State private var revealGeneration = 0

    /// The songs in the current scope, before search and sorting.
    var scopedSongs: [Song] {
        scope.songs(from: songs)
    }

    var sortedFolders: [SongFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var filteredSongs: [Song] {
        var result = scopedSongs

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

    /// The songs for `ids` in on-screen order.
    func songs(for ids: Set<UUID>) -> [Song] {
        filteredSongs.filter { ids.contains($0.id) }
    }

    var isBusy: Bool {
        isImportInProgress || isPreparingFolderSetup
    }

    private var isSelecting: Bool {
        #if os(macOS)
        !selection.isEmpty
        #else
        editMode.isEditing
        #endif
    }

    var body: some View {
        songActionDialogs(on: panelContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            #if os(iOS)
            .background(AppColors.backgroundSecondary)
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { iOSToolbar }
            .environment(\.editMode, $editMode)
            #else
            .overlay { folderDropHighlight }
            .onDrop(of: [.fileURL], delegate: LiveSetlistSongFolderDropDelegate(
                onHover: { isTargetedForFolderDrop = !isImportInProgress },
                onExit: { isTargetedForFolderDrop = false },
                onPerform: performFolderDrop
            ))
            #endif
            .onChange(of: searchText) { _, _ in
                // Never act on songs the search has hidden.
                selection.formIntersection(filteredSongs.map(\.id))
            }
            .onChange(of: scope.id) { _, _ in
                selection.removeAll()
            }
    }

    private var panelContent: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .zIndex(1)
                songList
                if isSelecting {
                    selectionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(AppAnimation.fadeQuick, value: isSelecting)

            if isBusy {
                importProgressOverlay
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            #if os(macOS)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(scope.title)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text("\(scopedSongs.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.textTertiary)
                Spacer(minLength: 0)
                addSongMenu
            }
            #endif

            HStack(spacing: AppSpacing.xs) {
                AppSearchField(text: $searchText, placeholder: "Search songs")
                sortMenu
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                ForEach(SongLibrarySortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            SongLibraryHeaderIcon(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort songs")
        .accessibilityLabel("Sort songs")
    }

    private var addSongMenu: some View {
        Menu {
            Button("Add Click Track…", systemImage: "metronome") {
                showingAddClickSheet = true
            }
            Button("Import Song Folder…", systemImage: "folder.badge.plus") {
                presentFolderImporter()
            }
        } label: {
            SongLibraryHeaderIcon(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isBusy)
        .help("Add song")
        .accessibilityLabel("Add song")
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var iOSToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            addSongMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(editMode.isEditing ? "Done" : "Select") {
                editMode = editMode.isEditing ? .inactive : .active
                selection.removeAll()
            }
            .disabled(scopedSongs.isEmpty)
        }
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

    @ViewBuilder
    private var songList: some View {
        if scopedSongs.isEmpty {
            scopeEmptyState
        } else if filteredSongs.isEmpty {
            emptyState(
                title: "No Results",
                systemImage: "magnifyingglass",
                description: "No songs match \"\(searchText)\"."
            )
        } else {
            ScrollViewReader { proxy in
                songCollection
                .contextMenu(forSelectionType: UUID.self) { ids in
                    songContextMenu(for: ids)
                } primaryAction: { ids in
                    // Double-click or Return on macOS, tap outside Select mode on iOS.
                    guard ids.count == 1, let song = songs(for: ids).first else { return }
                    onEdit(song)
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
                .modifier(SongListTopEdgeClipModifier())
                // List's minimum height is its content, so a new top row can
                // overflow upward and draw underneath the search bar.
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
                .onChange(of: songs.map(\.id)) { previousIDs, currentIDs in
                    selection.formIntersection(currentIDs)
                    revealInsertedSong(
                        previousIDs: previousIDs,
                        currentIDs: currentIDs,
                        proxy: proxy
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var songCollection: some View {
        #if os(macOS)
        List(selection: $selection) {
            ForEach(filteredSongs) { song in
                SongLibraryListRow(song: song)
                    .tag(song.id)
                    .draggable(SongDragPayload.string(for: song.id))
            }
        }
        .listStyle(.inset)
        .onDeleteCommand(perform: requestDeleteSelection)
        .onExitCommand { selection.removeAll() }
        #else
        List(selection: $selection) {
            Section {
                ForEach(filteredSongs) { song in
                    songRow(for: song)
                }
            } header: {
                SongLibraryColumnHeader()
            }
        }
        .listStyle(.plain)
        #endif
    }

    #if os(iOS)
    private func songRow(for song: Song) -> some View {
        SongLibraryRow(song: song) {
            onAddToSetlist(song)
        }
        .tag(song.id)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                songsPendingDelete = [song]
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    #endif

    private var selectionBar: some View {
        let selected = songs(for: selection)
        return SongLibrarySelectionBar(
            count: selected.count,
            onAddToSetlist: { addToSetlist(selected) },
            onDelete: { songsPendingDelete = selected }
        )
    }

    /// List keeps the previous scroll offset when a row is inserted at the top, which
    /// leaves the new song parked under the search bar. Scroll it into the list once
    /// that adjustment has settled.
    private func revealInsertedSong(
        previousIDs: [UUID],
        currentIDs: [UUID],
        proxy: ScrollViewProxy
    ) {
        let previous = Set(previousIDs)
        guard let targetID = currentIDs.first(where: { id in
            !previous.contains(id) && filteredSongs.contains { $0.id == id }
        }) else { return }

        revealGeneration += 1
        let generation = revealGeneration
        let persistentID = filteredSongs.first { $0.id == targetID }?.persistentModelID

        Task { @MainActor in
            await Task.yield()
            guard generation == revealGeneration else { return }
            scrollSongIntoView(targetID, persistentID: persistentID, proxy: proxy)

            try? await Task.sleep(for: .milliseconds(350))
            guard generation == revealGeneration else { return }
            scrollSongIntoView(targetID, persistentID: persistentID, proxy: proxy)
        }
    }

    private func scrollSongIntoView(
        _ id: UUID,
        persistentID: PersistentIdentifier?,
        proxy: ScrollViewProxy
    ) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let persistentID {
                proxy.scrollTo(persistentID, anchor: .top)
            }
            proxy.scrollTo(id, anchor: .top)
        }
    }
}

/// A borderless header icon with a fixed hit area so the menus line up.
private struct SongLibraryHeaderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
    }
}

#if os(iOS)
/// Column titles lined up with `SongLibraryRow`'s tempo and key columns.
private struct SongLibraryColumnHeader: View {
    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Text("Title")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("BPM")
                .frame(width: SongLibraryRow.tempoColumnWidth, alignment: .trailing)
            Text("Key")
                .frame(width: SongLibraryRow.keyColumnWidth, alignment: .center)
            Color.clear
                .frame(width: SongLibraryRow.addButtonWidth, height: 1)
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(AppColors.textTertiary)
        .accessibilityHidden(true)
    }
}
#endif

/// On iOS, stops list rows from drawing through the soft top edge into the search bar.
private struct SongListTopEdgeClipModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#Preview {
    SongLibraryPanel(
        onEdit: { _ in },
        onDismiss: {},
        onFoldersSelected: { _ in },
        onAddToSetlist: { _ in }
    )
        .frame(width: 300, height: 600)
        .modelContainer(for: [Song.self, AudioTrack.self], inMemory: true)
}
