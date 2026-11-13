import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension LivePlaybackView {
    var setlistHasSongs: Bool {
        workingSetlist.sortedEntries.contains { $0.song != nil }
    }

    var setlistSection: some View {
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
                    onInsertSongs: insertDroppedSongs,
                    sectionPlayback: setlistSectionPlayback,
                    rowHorizontalPadding: AppSpacing.xl
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, AppSpacing.sm)
            }
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
                    transition: setlist.hasNextSong(after: entry) ? entry.transition : nil,
                    sections: coordinator.waveformSnapshot(for: song)?.sections ?? []
                ))
            )
        }
    }

    private var setlistSectionPlayback: SetlistSectionPlayback {
        SetlistSectionPlayback(
            playheadTime: { coordinator.livePlayheadTime() },
            isPlaying: coordinator.isPlaying,
            // Only observe clock time while idle, so playback doesn't rebuild the list every tick.
            idlePlayheadTime: playbackClock.isPlaying ? nil : playbackClock.currentTime,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            selectSection: selectSection(songIndex:section:)
        )
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

    func songHasMissingMedia(_ song: Song) -> Bool {
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

    func presentOverlapEditor(for entry: SetlistEntry) {
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

    func presentOverlapEditor(forPlaybackIndex playbackIndex: Int) {
        guard let entry = workingSetlist.sortedEntries.first(where: {
            workingSetlist.playbackIndex(for: $0) == playbackIndex
        }) else {
            return
        }
        presentOverlapEditor(for: entry)
    }

    func songForEditing(id: UUID) -> Song? {
        workingSetlist.sortedEntries.compactMap(\.song).first(where: { $0.id == id })
            ?? allSongs.first(where: { $0.id == id })
    }

    func addSong(_ song: Song, at index: Int) {
        viewModel.insertSong(song, at: index, to: workingSetlist, context: modelContext)
        coordinator.syncSetlist(workingSetlist)
    }

    func addHeader() {
        let index = workingSetlist.sortedEntries.count
        viewModel.insertHeader(title: "New Header", at: index, to: workingSetlist, context: modelContext)
        if let entry = workingSetlist.sortedEntries.last(where: { $0.isHeader }) {
            isCreatingHeader = true
            headerPendingEdit = entry
            editHeaderTitle = entry.headerTitle ?? "New Header"
            editHeaderTimeSeconds = entry.headerTimeSeconds ?? 0
        }
    }

    func saveHeaderEdit() {
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

    func dismissHeaderEdit() {
        headerPendingEdit = nil
        isCreatingHeader = false
    }
}
