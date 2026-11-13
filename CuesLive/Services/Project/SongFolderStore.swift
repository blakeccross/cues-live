import Foundation
import SwiftData

/// Creates, renames, and deletes song folders, and moves songs between them.
@MainActor
enum SongFolderStore {
    /// Inserts a folder named "New Folder", or "New Folder 2"… when that name is taken.
    @discardableResult
    static func create(existingNames: Set<String>, context: ModelContext) throws -> SongFolder {
        let folder = SongFolder(name: uniqueName(existingNames: existingNames))
        context.insert(folder)
        try context.save()
        return folder
    }

    /// Renames the folder. Blank names are ignored so a folder never ends up untitled.
    static func rename(_ folder: SongFolder, to name: String, context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        folder.name = trimmed
        try context.save()
    }

    /// Deletes the folder. Its songs stay in the library, outside any folder.
    static func delete(_ folder: SongFolder, context: ModelContext) throws {
        for song in folder.songs {
            song.folder = nil
        }
        context.delete(folder)
        try context.save()
    }

    /// Moves the songs into `folder`, or out of any folder when `folder` is nil.
    static func move(_ songs: [Song], to folder: SongFolder?, context: ModelContext) throws {
        guard !songs.isEmpty else { return }
        for song in songs {
            song.folder = folder
        }
        try context.save()
    }

    static func uniqueName(existingNames: Set<String>) -> String {
        let base = SongFolder.defaultName
        guard existingNames.contains(base) else { return base }
        var index = 2
        while existingNames.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}
