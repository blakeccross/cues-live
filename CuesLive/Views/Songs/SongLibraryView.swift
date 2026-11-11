import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

private enum SongLibrarySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case name = "Name"

    var id: String { rawValue }
}

struct SongLibraryPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]

    var onEdit: (Song) -> Void
    var onDismiss: () -> Void
    var onFoldersSelected: ([SongFolderImporter.ImportRequest]) -> Void
    var onAddToSetlist: (Song) -> Void
    var isImportInProgress = false

    @State private var searchText = ""
    @State private var sortOrder: SongLibrarySortOrder = .newest
    @State private var showingAddSongOptions = false
    @State private var showingAddClickSheet = false
    @State private var folderSetupSession: SongFolderSetupSession?
    @State private var isPreparingFolderSetup = false
    @State private var songPendingRename: Song?
    @State private var renameSongName = ""
    @State private var songPendingDelete: Song?
    @State private var createSongError: String?
    @State private var songActionError: String?
    #if os(macOS)
    @State private var isTargetedForFolderDrop = false
    #else
    @State private var showingFolderImporter = false
    #endif
    @State private var consolidateSummary: String?
    /// Bumps when a newer import should cancel an in-flight scroll-into-view.
    @State private var revealGeneration = 0

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredSongs: [Song] {
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
        ZStack {
            VStack(spacing: 0) {
                searchBar
                    .zIndex(1)
                songList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isImportInProgress || isPreparingFolderSetup {
                importProgressOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .background(AppColors.backgroundSecondary)
        #endif
        #if os(macOS)
        .overlay {
            if isTargetedForFolderDrop {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.accent, lineWidth: 2)
                    .padding(AppSpacing.xs)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], delegate: LiveSetlistSongFolderDropDelegate(
            onHover: { isTargetedForFolderDrop = !isImportInProgress },
            onExit: { isTargetedForFolderDrop = false },
            onPerform: performFolderDrop
        ))
        #endif
        #if os(iOS)
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingAddSongOptions = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isImportInProgress || isPreparingFolderSetup)
                .accessibilityLabel("Add song")
                .confirmationDialog(
                    "Add Song",
                    isPresented: $showingAddSongOptions,
                    titleVisibility: .visible
                ) {
                    Button("Add Click") {
                        showingAddClickSheet = true
                    }
                    Button("Import from Folder") {
                        presentFolderImporter()
                    }
                    Button("Cancel", role: .cancel) {}
                }
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
        .alert("Could Not Create Song", isPresented: Binding(
            get: { createSongError != nil },
            set: { if !$0 { createSongError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(createSongError ?? "")
        }
        .alert("Rename Song", isPresented: Binding(
            get: { songPendingRename != nil },
            set: { if !$0 { songPendingRename = nil } }
        )) {
            TextField("Song name", text: $renameSongName)
            Button("Rename") {
                renameSong()
            }
            Button("Cancel", role: .cancel) {
                songPendingRename = nil
            }
        }
        .confirmationDialog(
            "Remove Song",
            isPresented: Binding(
                get: { songPendingDelete != nil },
                set: { if !$0 { songPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let song = songPendingDelete {
                    removeSong(song)
                }
                songPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                songPendingDelete = nil
            }
        } message: {
            if let song = songPendingDelete {
                Text("\"\(song.name)\" and its tracks will be permanently deleted.")
            }
        }
        .alert("Could Not Update Song", isPresented: Binding(
            get: { songActionError != nil },
            set: { if !$0 { songActionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(songActionError ?? "")
        }
        #if !os(macOS)
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
        #endif
        .alert("Media Consolidated", isPresented: Binding(
            get: { consolidateSummary != nil },
            set: { if !$0 { consolidateSummary = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(consolidateSummary ?? "")
        }
        .sheet(isPresented: $showingAddClickSheet) {
            AddClickSongSheet { name, bpm, numerator, denominator in
                createClickSong(
                    name: name,
                    bpm: bpm,
                    numerator: numerator,
                    denominator: denominator
                )
            }
        }
        .sheet(item: $folderSetupSession) { session in
            SongFolderSetupSheet(previews: session.previews) { requests in
                folderSetupSession = nil
                guard !requests.isEmpty else { return }
                onFoldersSelected(requests)
            }
        }
    }

    private var addSongButton: some View {
        Button {
            showingAddSongOptions = true
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appLinkPointer()
        .disabled(isImportInProgress || isPreparingFolderSetup)
        .help("Add song")
        .accessibilityLabel("Add song")
        .confirmationDialog(
            "Add Song",
            isPresented: $showingAddSongOptions,
            titleVisibility: .visible
        ) {
            Button("Add Click") {
                showingAddClickSheet = true
            }
            Button("Import from Folder") {
                presentFolderImporter()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .tint(AppColors.accent)
                Text(isPreparingFolderSetup ? "Reading song folder…" : "Importing song folder…")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(AppSpacing.xl)
            .background(AppColors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
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
                    ForEach(SongLibrarySortOrder.allCases) { order in
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
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Sort songs")

            #if os(macOS)
            addSongButton
            #endif
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.xs)
        .padding(.bottom, AppSpacing.xs)
        #if os(iOS)
        .background(AppColors.backgroundSecondary)
        #endif
    }

    @ViewBuilder
    private var songList: some View {
        if songs.isEmpty {
            AppEmptyState(
                title: "No Songs Yet",
                systemImage: "music.note",
                description: "Import a folder with multitrack stems and an Ableton file, or add a click track."
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
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredSongs) { song in
                        SongLibraryRow(
                            song: song,
                            onSelect: { onEdit(song) },
                            onAddToSetlist: { onAddToSetlist(song) }
                        )
                        #if os(macOS)
                        .draggable(SongDragPayload.string(for: song.id))
                        #endif
                        .contextMenu {
                            songContextMenu(for: song)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                songPendingDelete = song
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowSeparatorTint(AppColors.separator)
                .contentMargins(.top, 0, for: .scrollContent)
                .modifier(SongListTopEdgeClipModifier())
                .scrollClipDisabled(false)
                // List's minimum height is its content, so a new top row can
                // overflow upward and draw underneath the search bar.
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
                .onChange(of: songs.map(\.id)) { previousIDs, currentIDs in
                    revealInsertedSong(
                        previousIDs: previousIDs,
                        currentIDs: currentIDs,
                        proxy: proxy
                    )
                }
            }
        }
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

    @ViewBuilder
    private func songContextMenu(for song: Song) -> some View {
        Button {
            onEdit(song)
        } label: {
            Label("Edit Song", systemImage: "pencil")
        }
        Button("Rename") {
            songPendingRename = song
            renameSongName = song.name
        }
        Button("Duplicate") {
            duplicateSong(song)
        }
        if SongProjectBridge.projectURL(for: song) != nil {
            Button("Consolidate Media…") {
                consolidateMedia(for: song)
            }
        }
        Divider()
        Button("Remove", role: .destructive) {
            songPendingDelete = song
        }
    }

    private func createClickSong(
        name: String,
        bpm: Double,
        numerator: Int,
        denominator: Int
    ) {
        do {
            let song = try ClickSongCreator.create(
                name: name,
                bpm: bpm,
                numerator: numerator,
                denominator: denominator,
                context: modelContext
            )
            showingAddClickSheet = false
            onEdit(song)
        } catch {
            createSongError = error.localizedDescription
        }
    }

    private func renameSong() {
        let trimmed = renameSongName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let song = songPendingRename, !trimmed.isEmpty else {
            songPendingRename = nil
            return
        }

        song.name = trimmed
        do {
            try modelContext.save()
            try SongProjectBridge.syncProjectFile(for: song, context: modelContext)
            songPendingRename = nil
        } catch {
            songActionError = error.localizedDescription
        }
    }

    private func duplicateSong(_ source: Song) {
        let copy = Song(name: duplicateName(for: source.name))
        copy.bpm = source.bpm
        copy.timeSignatureNumerator = source.timeSignatureNumerator
        copy.timeSignatureDenominator = source.timeSignatureDenominator
        copy.baseKeyRaw = source.baseKeyRaw
        copy.transposeSemitones = source.transposeSemitones
        copy.smartGuideEnabled = source.smartGuideEnabled
        modelContext.insert(copy)

        var trackIDMap: [UUID: UUID] = [:]

        do {
            for track in source.sortedTracks {
                let newTrackID = UUID()
                trackIDMap[track.id] = newTrackID

                let newTrack = AudioTrack(
                    displayName: track.displayName,
                    relativeFilePath: track.relativeFilePath,
                    sortOrder: track.sortOrder
                )
                newTrack.id = newTrackID
                newTrack.volume = track.volume
                newTrack.pan = track.pan
                newTrack.isMuted = track.isMuted
                newTrack.isSolo = track.isSolo
                newTrack.trimStartSeconds = track.trimStartSeconds
                newTrack.trimEndSeconds = track.trimEndSeconds
                newTrack.includeInKeyChange = track.includeInKeyChange
                newTrack.sourceDurationSeconds = track.sourceDurationSeconds
                newTrack.mediaPath = track.mediaPath
                newTrack.mediaPathStyle = track.mediaPathStyle
                newTrack.mediaBookmarkData = track.mediaBookmarkData
                newTrack.group = track.group
                newTrack.song = copy
                modelContext.insert(newTrack)
                copy.tracks.append(newTrack)
            }

            let sourceState = try SongProjectBridge.loadProjectState(for: source)
            var timeline = sourceState.timeline
            timeline.clips = timeline.clips.map { clip in
                TrackClip(
                    trackID: trackIDMap[clip.trackID] ?? clip.trackID,
                    timelineStartSeconds: clip.timelineStartSeconds,
                    duration: clip.duration,
                    sourceStartSeconds: clip.sourceStartSeconds,
                    gainDB: clip.gainDB
                )
            }
            let midiEvents = sourceState.midiEvents.map { event in
                MIDIEvent(
                    id: event.id,
                    trackID: trackIDMap[event.trackID] ?? event.trackID,
                    timelineSeconds: event.timelineSeconds,
                    commandID: event.commandID,
                    label: event.label
                )
            }

            try modelContext.save()
            try SongProjectBridge.syncProjectFile(
                for: copy,
                context: modelContext,
                timeline: timeline,
                tempoChanges: sourceState.tempoChanges,
                timeSignatureChanges: sourceState.timeSignatureChanges,
                midiEvents: midiEvents
            )
        } catch {
            modelContext.delete(copy)
            FileStore.deleteProjectFile(for: copy)
            songActionError = error.localizedDescription
        }
    }

    private func consolidateMedia(for song: Song) {
        do {
            let stemsDirectory = try MediaConsolidator.consolidate(for: song, context: modelContext)
            consolidateSummary = "Copied media to \(stemsDirectory.path)."
        } catch {
            songActionError = error.localizedDescription
        }
    }

    private func queueFolderImport(_ folderURLs: [URL]) {
        guard !isImportInProgress, !isPreparingFolderSetup, folderSetupSession == nil else { return }
        guard !folderURLs.isEmpty else { return }

        isPreparingFolderSetup = true
        let urls = folderURLs
        Task { @MainActor in
            await Task.yield()
            defer { isPreparingFolderSetup = false }

            var previews: [SongFolderImporter.Preview] = []
            var failures: [String] = []
            for url in urls {
                do {
                    let preview = try await Task.detached(priority: .userInitiated) {
                        try SongFolderImporter.previewFolder(at: url)
                    }.value
                    previews.append(preview)
                } catch {
                    failures.append(
                        urls.count == 1
                            ? error.localizedDescription
                            : "\(url.lastPathComponent): \(error.localizedDescription)"
                    )
                }
            }

            if !failures.isEmpty {
                songActionError = failures.joined(separator: "\n")
            }
            guard !previews.isEmpty else { return }
            folderSetupSession = SongFolderSetupSession(previews: previews)
        }
    }

    private func presentFolderImporter() {
        guard !isImportInProgress, !isPreparingFolderSetup, folderSetupSession == nil else { return }
        #if os(macOS)
        // SwiftUI `.fileImporter` often fails to present from a Menu. Use NSOpenPanel after
        // the menu finishes dismissing so Finder reliably appears.
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.prompt = "Import"
            panel.message = "Choose a song folder with stems (and an optional Ableton Live Set)."
            guard panel.runModal() == .OK, let folderURL = panel.url else { return }
            queueFolderImport([folderURL])
        }
        #else
        showingFolderImporter = true
        #endif
    }

    #if !os(macOS)
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            songActionError = error.localizedDescription
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            queueFolderImport([folderURL])
        }
    }
    #endif

    #if os(macOS)
    /// Handles a Finder drag dropped onto the library: each dropped folder is imported as a new song.
    private func performFolderDrop(_ providers: [NSItemProvider]) -> Bool {
        isTargetedForFolderDrop = false
        guard !providers.isEmpty, !isImportInProgress, !isPreparingFolderSetup, folderSetupSession == nil else {
            return false
        }

        Task { @MainActor in
            let folderURLs = await SongFolderDrop.folderURLs(from: providers)
            guard !folderURLs.isEmpty else {
                songActionError = "Drop a folder containing audio files to add a song."
                return
            }
            queueFolderImport(folderURLs)
        }
        return true
    }
    #endif

    private func removeSong(_ song: Song) {
        let songID = song.id

        if let entries = try? modelContext.fetch(FetchDescriptor<SetlistEntry>()) {
            for entry in entries where entry.song?.id == songID {
                entry.setlist?.entries.removeAll { $0 === entry }
                modelContext.delete(entry)
            }
        }

        modelContext.delete(song)

        do {
            try modelContext.save()
            FileStore.deleteProjectFile(for: song)
        } catch {
            songActionError = error.localizedDescription
        }
    }

    private func duplicateName(for baseName: String) -> String {
        let existingNames = Set(songs.map(\.name))
        let firstCandidate = "\(baseName) Copy"
        if !existingNames.contains(firstCandidate) {
            return firstCandidate
        }

        var index = 2
        while existingNames.contains("\(baseName) Copy \(index)") {
            index += 1
        }
        return "\(baseName) Copy \(index)"
    }
}

/// Stops list rows from drawing through the soft top edge into the search bar.
private struct SongListTopEdgeClipModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

private struct SongLibraryRow: View {
    let song: Song
    let onSelect: () -> Void
    let onAddToSetlist: () -> Void

    private var subtitle: String {
        let trackText = song.tracks.isEmpty ? "No tracks" : "\(song.tracks.count) tracks"
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
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            Spacer(minLength: 0)

            if song.smartGuideEnabled {
                SmartGuideBadge()
            }

            Button {
                onAddToSetlist()
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appLinkPointer()
            .accessibilityLabel("Add to setlist")
        }
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
