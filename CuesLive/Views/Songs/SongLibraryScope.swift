import Foundation

/// Which songs the library lists: everything, or one folder.
enum SongLibraryScope {
    case allSongs
    case folder(SongFolder)

    var title: String {
        switch self {
        case .allSongs: "All Songs"
        case .folder(let folder): folder.name
        }
    }

    /// Changes whenever the scope points at a different collection.
    var id: UUID? {
        folder?.id
    }

    var folder: SongFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }

    func songs(from library: [Song]) -> [Song] {
        switch self {
        case .allSongs: library
        case .folder(let folder): library.filter { $0.folder?.id == folder.id }
        }
    }
}
