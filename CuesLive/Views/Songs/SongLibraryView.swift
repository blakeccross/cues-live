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
    var onFolderSelected: (URL) -> Void
    var onAddToSetlist: (Song) -> Void
    var isImportInProgress = false

    @State private var searchText = ""
    @State private var sortOrder: SongLibrarySortOrder = .newest
    @State private var showingAddSongOptions = false
    @State private var showingAddClickSheet = false
    @State private var songPendingRename: Song?
    @State private var renameSongName = ""
    @State private var songPendingDelete: Song?
    @State private var createSongError: String?
    @State private var songActionError: String?
    #if !os(macOS)
    @State private var showingFolderImporter = false
    #endif
    @State private var consolidateSummary: String?

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
                #if os(macOS)
                headerBar
                #endif
                searchBar
                songList
            }

            if isImportInProgress {
                importProgressOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.backgroundSecondary)
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
                .disabled(isImportInProgress)
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
    }

    private var headerBar: some View {
        ZStack {
            Text("Songs")
                .appLargeTitle()

            HStack {
                Spacer()

                Button {
                    showingAddSongOptions = true
                } label: {
                    headerIcon("plus")
                }
                .buttonStyle(.plain)
                .appLinkPointer()
                .disabled(isImportInProgress)
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
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
    }

    private func headerIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppColors.accent)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .tint(AppColors.accent)
                Text("Importing song folder…")
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
            List {
                ForEach(filteredSongs) { song in
                    SongLibraryRow(
                        song: song,
                        onSelect: { onEdit(song) },
                        onAddToSetlist: { onAddToSetlist(song) }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
        copy.transposeHighQuality = source.transposeHighQuality
        copy.dynamicCuesEnabled = source.dynamicCuesEnabled
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
                newTrack.isMuted = track.isMuted
                newTrack.isSolo = track.isSolo
                newTrack.trimStartSeconds = track.trimStartSeconds
                newTrack.trimEndSeconds = track.trimEndSeconds
                newTrack.excludeFromTranspose = track.excludeFromTranspose
                newTrack.mediaPath = track.mediaPath
                newTrack.mediaPathStyle = track.mediaPathStyle
                newTrack.mediaBookmarkData = track.mediaBookmarkData
                newTrack.group = track.group
                newTrack.song = copy
                modelContext.insert(newTrack)
                copy.tracks.append(newTrack)
            }

            let sourceState = try SongProjectBridge.loadProjectState(for: source)
            var arrangement = sourceState.arrangement
            arrangement.clipTrims = arrangement.clipTrims.map { trim in
                ArrangementClipTrim(
                    slotID: trim.slotID,
                    trackID: trackIDMap[trim.trackID] ?? trim.trackID,
                    leadingTrim: trim.leadingTrim,
                    trailingTrim: trim.trailingTrim
                )
            }
            arrangement.removedClips = arrangement.removedClips.map { removed in
                ArrangementRemovedClip(
                    slotID: removed.slotID,
                    trackID: trackIDMap[removed.trackID] ?? removed.trackID
                )
            }
            arrangement.clipGaps = arrangement.clipGaps.map { gap in
                ArrangementClipGap(
                    slotID: gap.slotID,
                    trackID: trackIDMap[gap.trackID] ?? gap.trackID,
                    sourceStartSeconds: gap.sourceStartSeconds,
                    sourceEndSeconds: gap.sourceEndSeconds
                )
            }
            arrangement.clipRegions = arrangement.clipRegions.map { region in
                ClipRegion(
                    id: region.id,
                    slotID: region.slotID,
                    trackID: trackIDMap[region.trackID] ?? region.trackID,
                    markerID: region.markerID,
                    sourceStartSeconds: region.sourceStartSeconds,
                    sourceEndSeconds: region.sourceEndSeconds,
                    timelineStartSeconds: region.timelineStartSeconds,
                    timelineEndSeconds: region.timelineEndSeconds
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
                markers: sourceState.markers,
                arrangement: arrangement,
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

    private func presentFolderImporter() {
        guard !isImportInProgress else { return }
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
            onFolderSelected(folderURL)
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
            onFolderSelected(folderURL)
        }
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
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            Spacer(minLength: 0)

            Button {
                onAddToSetlist()
            } label: {
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

private struct AddClickSongSheet: View {
    var onCreate: (String, Double, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var songName = ""
    @State private var bpmText = "120"
    @State private var numerator = TimeSignatureChange.defaultNumerator
    @State private var denominator = TimeSignatureChange.defaultDenominator

    private static let presets: [(numerator: Int, denominator: Int)] = [
        (4, 4), (3, 4), (2, 4), (6, 8), (5, 4), (7, 8), (12, 8)
    ]

    private var canCreate: Bool {
        !songName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedBPM != nil
    }

    private var parsedBPM: Double? {
        let sanitized = bpmText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(sanitized), value > 0, value.isFinite else {
            return nil
        }
        return min(
            max(value, TempoChange.validBPMRange.lowerBound),
            TempoChange.validBPMRange.upperBound
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Song name", text: $songName)
                    TextField("Tempo (BPM)", text: $bpmText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }

                Section("Meter") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                            Button {
                                numerator = preset.numerator
                                denominator = preset.denominator
                            } label: {
                                Text("\(preset.numerator)/\(preset.denominator)")
                                    .font(.body.monospacedDigit().weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .appEditorToolbarPill()
                            .tint(
                                numerator == preset.numerator && denominator == preset.denominator
                                    ? AppColors.accent
                                    : .secondary
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section {
                    Text("Creates an 8-bar click track set to loop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Click")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let bpm = parsedBPM else { return }
                        onCreate(
                            songName.trimmingCharacters(in: .whitespacesAndNewlines),
                            bpm,
                            numerator,
                            denominator
                        )
                    }
                    .disabled(!canCreate)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 380)
        #endif
    }
}

#Preview {
    SongLibraryPanel(
        onEdit: { _ in },
        onDismiss: {},
        onFolderSelected: { _ in },
        onAddToSetlist: { _ in }
    )
        .frame(width: 300, height: 600)
        .modelContainer(for: [Song.self, AudioTrack.self], inMemory: true)
}
