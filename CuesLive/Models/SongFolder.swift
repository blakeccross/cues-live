import Foundation
import SwiftData

/// A user folder in the song library. A song sits in at most one folder and always
/// appears in All Songs. Deleting a folder leaves its songs in the library.
@Model
final class SongFolder {
    static let defaultName = "New Folder"

    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Song.folder)
    var songs: [Song]

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
        songs = []
    }
}
