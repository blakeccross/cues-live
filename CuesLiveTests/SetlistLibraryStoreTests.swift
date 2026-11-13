import SwiftData
import XCTest
@testable import CuesLive

@MainActor
final class SetlistLibraryStoreTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func testRenameTrimsAndIgnoresBlankNames() throws {
        let context = try makeContext()
        let setlist = Setlist(name: "Sunday")
        context.insert(setlist)

        try SetlistLibraryStore.rename(setlist, to: "   ", context: context)
        XCTAssertEqual(setlist.name, "Sunday")

        try SetlistLibraryStore.rename(setlist, to: " Easter ", context: context)
        XCTAssertEqual(setlist.name, "Easter")
    }

    func testDuplicateCopiesEntriesInOrder() throws {
        let context = try makeContext()
        let song = Song(name: "Opener")
        context.insert(song)
        let source = Setlist(name: "Sunday")
        context.insert(source)

        let header = SetlistEntry(sortOrder: 0, headerTitle: "Worship", headerTimeSeconds: 60)
        let songEntry = SetlistEntry(sortOrder: 1, song: song, transition: .overlap)
        songEntry.overlapStartOffsetSeconds = 4
        for entry in [header, songEntry] {
            entry.setlist = source
            context.insert(entry)
            source.entries.append(entry)
        }
        try context.save()

        let copy = try SetlistLibraryStore.duplicate(source, existingNames: ["Sunday"], context: context)

        XCTAssertEqual(copy.name, "Sunday Copy")
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertNil(copy.showFilePath)
        let entries = copy.sortedEntries
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].headerTitle, "Worship")
        XCTAssertEqual(entries[0].headerTimeSeconds, 60)
        XCTAssertEqual(entries[1].song?.id, song.id)
        XCTAssertEqual(entries[1].transition, .overlap)
        XCTAssertEqual(entries[1].overlapStartOffsetSeconds, 4)
        XCTAssertEqual(source.entries.count, 2)
    }

    func testDeleteRemovesSetlistAndEntriesButKeepsSongs() throws {
        let context = try makeContext()
        let song = Song(name: "Kept")
        context.insert(song)
        let setlist = Setlist(name: "Gone")
        context.insert(setlist)
        let entry = SetlistEntry(sortOrder: 0, song: song)
        entry.setlist = setlist
        context.insert(entry)
        setlist.entries.append(entry)
        try context.save()

        try SetlistLibraryStore.delete(setlist, context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<Setlist>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SetlistEntry>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Song>()).map(\.name), ["Kept"])
    }

    func testOnlyFilesInShowsFolderAreManaged() {
        let managed = ShowFileStore.showsDirectory.appendingPathComponent("Sunday.cueshow")
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("Sunday.cueshow")
        XCTAssertTrue(SetlistLibraryStore.isManagedShowFile(managed))
        XCTAssertFalse(SetlistLibraryStore.isManagedShowFile(external))
    }
}
