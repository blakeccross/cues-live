import SwiftData
import XCTest
@testable import CuesLive

@MainActor
final class SongFolderStoreTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func testUniqueNameSkipsTakenNames() {
        XCTAssertEqual(SongFolderStore.uniqueName(existingNames: []), "New Folder")
        XCTAssertEqual(
            SongFolderStore.uniqueName(existingNames: ["New Folder", "New Folder 2"]),
            "New Folder 3"
        )
    }

    func testMoveAssignsAndClearsFolder() throws {
        let context = try makeContext()
        let song = Song(name: "Song")
        context.insert(song)
        let folder = try SongFolderStore.create(existingNames: [], context: context)

        try SongFolderStore.move([song], to: folder, context: context)
        XCTAssertEqual(song.folder?.id, folder.id)
        XCTAssertEqual(folder.songs.map(\.name), ["Song"])

        try SongFolderStore.move([song], to: nil, context: context)
        XCTAssertNil(song.folder)
        XCTAssertTrue(folder.songs.isEmpty)
    }

    func testDeleteKeepsSongsInLibrary() throws {
        let context = try makeContext()
        let song = Song(name: "Kept")
        context.insert(song)
        let folder = try SongFolderStore.create(existingNames: [], context: context)
        try SongFolderStore.move([song], to: folder, context: context)

        try SongFolderStore.delete(folder, context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFolder>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Song>()).map(\.name), ["Kept"])
        XCTAssertNil(song.folder)
    }

    func testRenameIgnoresBlankNames() throws {
        let context = try makeContext()
        let folder = try SongFolderStore.create(existingNames: [], context: context)

        try SongFolderStore.rename(folder, to: "   ", context: context)
        XCTAssertEqual(folder.name, "New Folder")

        try SongFolderStore.rename(folder, to: " Christmas ", context: context)
        XCTAssertEqual(folder.name, "Christmas")
    }
}
