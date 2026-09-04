import Foundation
import SwiftData

final class SetlistViewModel {
    func insertSong(_ song: Song, at index: Int, to setlist: Setlist, context: ModelContext) {
        let entry = SetlistEntry(sortOrder: 0, song: song)
        entry.setlist = setlist
        insertEntry(entry, at: index, in: setlist, context: context)
    }

    func insertHeader(
        title: String,
        timeSeconds: TimeInterval? = nil,
        at index: Int,
        to setlist: Setlist,
        context: ModelContext
    ) {
        let entry = SetlistEntry(sortOrder: 0, headerTitle: title, headerTimeSeconds: timeSeconds)
        entry.setlist = setlist
        insertEntry(entry, at: index, in: setlist, context: context)
    }

    func updateHeader(
        _ entry: SetlistEntry,
        title: String,
        timeSeconds: TimeInterval?,
        context: ModelContext
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entry.isHeader, let setlist = entry.setlist else { return }
        entry.headerTitle = trimmed
        entry.headerTimeSeconds = timeSeconds.map { max(0, $0) }
        persistSetlist(setlist, context: context)
    }

    func renameHeader(_ entry: SetlistEntry, title: String, context: ModelContext) {
        updateHeader(entry, title: title, timeSeconds: entry.headerTimeSeconds, context: context)
    }

    func removeEntry(_ entry: SetlistEntry, from setlist: Setlist, context: ModelContext) {
        setlist.entries.removeAll { $0 === entry }
        normalizeSortOrder(for: setlist)
        context.delete(entry)
        persistSetlist(setlist, context: context)
    }

    func moveEntries(in setlist: Setlist, from source: IndexSet, to destination: Int, context: ModelContext) {
        let movedEntries = applyMove(in: setlist, from: source, to: destination)
        clearOverlapTransitions(for: movedEntries)
        persistSetlist(setlist, context: context)
    }

    /// Reorders in memory only. Saving on every step of a drag would stall on disk writes,
    /// so callers pair this with `commitEntryOrder` once the drag finishes.
    func previewMoveEntries(in setlist: Setlist, from source: IndexSet, to destination: Int) {
        applyMove(in: setlist, from: source, to: destination)
    }

    func commitEntryOrder(in setlist: Setlist, movedEntries: [SetlistEntry], context: ModelContext) {
        clearOverlapTransitions(for: movedEntries)
        persistSetlist(setlist, context: context)
    }

    func setTransition(_ transition: SetlistTransition, for entry: SetlistEntry, context: ModelContext) {
        guard let setlist = entry.setlist else { return }
        entry.transition = transition
        persistSetlist(setlist, context: context)
    }

    func setOverlapTransition(
        _ config: OverlapTransitionConfig,
        for entry: SetlistEntry,
        context: ModelContext
    ) {
        guard let setlist = entry.setlist else { return }
        entry.overlapConfig = config
        entry.transition = .overlap
        persistSetlist(setlist, context: context)
    }

    @discardableResult
    private func applyMove(in setlist: Setlist, from source: IndexSet, to destination: Int) -> [SetlistEntry] {
        var sorted = setlist.sortedEntries
        let movedEntries = source.map { sorted[$0] }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in sorted.enumerated() {
            entry.sortOrder = index
        }
        return movedEntries
    }

    private func clearOverlapTransitions(for entries: [SetlistEntry]) {
        for entry in entries where entry.transition == .overlap {
            entry.transition = .continue
        }
    }

    private func insertEntry(_ entry: SetlistEntry, at index: Int, in setlist: Setlist, context: ModelContext) {
        setlist.entries.append(entry)

        var sorted = setlist.sortedEntries
        guard let entryIndex = sorted.firstIndex(where: { $0 === entry }) else { return }
        sorted.remove(at: entryIndex)
        let clampedIndex = min(max(0, index), sorted.count)
        sorted.insert(entry, at: clampedIndex)
        for (idx, item) in sorted.enumerated() {
            item.sortOrder = idx
        }
        persistSetlist(setlist, context: context)
    }

    private func persistSetlist(_ setlist: Setlist, context: ModelContext) {
        try? context.save()
        try? SongProjectBridge.persistShow(for: setlist, context: context)
    }

    private func normalizeSortOrder(for setlist: Setlist) {
        for (index, entry) in setlist.sortedEntries.enumerated() {
            entry.sortOrder = index
        }
    }
}
