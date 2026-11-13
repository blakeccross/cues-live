import Foundation
import SwiftData

/// Library-level setlist operations: renaming, duplicating, and deleting setlists
/// along with the `.cueshow` files the app manages for them.
@MainActor
enum SetlistLibraryStore {
    /// Renames the setlist and rewrites its show file. A file in the app's Shows folder is
    /// renamed to match; a file the user saved elsewhere keeps its name and location.
    static func rename(_ setlist: Setlist, to name: String, context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != setlist.name else { return }
        setlist.name = trimmed
        try context.save()

        guard let showURL = setlist.showFilePath.map(URL.init(fileURLWithPath:)) else { return }
        let renamedURL = isManagedShowFile(showURL) ? ShowFileStore.defaultShowURL(for: trimmed) : nil
        try SongProjectBridge.persistShow(for: setlist, to: renamedURL, context: context)
    }

    /// Copies the setlist's songs, headers, and transitions under an unused "Copy" name.
    /// The copy has no show file until it is saved.
    @discardableResult
    static func duplicate(_ source: Setlist, existingNames: Set<String>, context: ModelContext) throws -> Setlist {
        let copy = Setlist(name: SongLibraryStore.duplicateName(for: source.name, existingNames: existingNames))
        context.insert(copy)

        for entry in source.sortedEntries {
            let newEntry: SetlistEntry
            if let song = entry.song {
                newEntry = SetlistEntry(sortOrder: entry.sortOrder, song: song, transition: entry.transition)
                newEntry.overlapStartOffsetSeconds = entry.overlapStartOffsetSeconds
            } else if let headerTitle = entry.headerTitle {
                newEntry = SetlistEntry(
                    sortOrder: entry.sortOrder,
                    headerTitle: headerTitle,
                    headerTimeSeconds: entry.headerTimeSeconds
                )
            } else {
                continue
            }
            newEntry.setlist = copy
            context.insert(newEntry)
            copy.entries.append(newEntry)
        }

        try context.save()
        return copy
    }

    /// Deletes the setlist and its entries. Its show file is removed only when it lives in the
    /// app's Shows folder, which is restored on launch; files saved elsewhere are left alone.
    static func delete(_ setlist: Setlist, context: ModelContext) throws {
        let managedFile = setlist.showFilePath
            .map(URL.init(fileURLWithPath:))
            .flatMap { isManagedShowFile($0) ? $0 : nil }

        context.delete(setlist)
        try context.save()

        if let managedFile {
            try? FileManager.default.removeItem(at: managedFile)
        }
    }

    static func isManagedShowFile(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent() == ShowFileStore.showsDirectory.standardizedFileURL
    }
}
