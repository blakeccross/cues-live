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

    /// Removes every given entry in one save. Entries that belong to another setlist are ignored.
    func removeEntries(_ entries: [SetlistEntry], from setlist: Setlist, context: ModelContext) {
        let removed = entries.filter { entry in setlist.entries.contains { $0 === entry } }
        guard !removed.isEmpty else { return }
        setlist.entries.removeAll { entry in removed.contains { $0 === entry } }
        normalizeSortOrder(for: setlist)
        for entry in removed {
            context.delete(entry)
        }
        persistSetlist(setlist, context: context)
    }

    /// Reorders entries. A drop that leaves the order unchanged does nothing, so it can't reset
    /// the moved entries' overlap transitions.
    func moveEntries(in setlist: Setlist, from source: IndexSet, to destination: Int, context: ModelContext) {
        let sorted = setlist.sortedEntries
        var reordered = sorted
        reordered.move(fromOffsets: source, toOffset: destination)
        guard !zip(sorted, reordered).allSatisfy({ $0 === $1 }) else { return }
        let movedEntries = applyMove(in: setlist, from: source, to: destination)
        clearOverlapTransitions(for: movedEntries)
        persistSetlist(setlist, context: context)
    }

    /// Moves `entries` as one block, keeping their relative order, so they land directly before
    /// `target`, or at the end when `target` is nil. A target that is itself being moved is
    /// treated as the next unmoved entry after it.
    func moveEntries(
        _ entries: [SetlistEntry],
        before target: SetlistEntry?,
        in setlist: Setlist,
        context: ModelContext
    ) {
        let sorted = setlist.sortedEntries
        let source = IndexSet(entries.compactMap { entry in sorted.firstIndex { $0 === entry } })
        guard !source.isEmpty else { return }
        let targetOffset = target.flatMap { target in sorted.firstIndex { $0 === target } } ?? sorted.count
        let destination = sorted.indices[targetOffset...].first { !source.contains($0) } ?? sorted.count
        moveEntries(in: setlist, from: source, to: destination, context: context)
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
