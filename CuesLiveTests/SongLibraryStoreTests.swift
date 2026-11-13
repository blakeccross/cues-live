import SwiftData
import XCTest
@testable import CuesLive

@MainActor
final class SongLibraryStoreTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func testDeleteRemovesSelectedSongsAndTheirSetlistEntries() throws {
        let context = try makeContext()
        let first = Song(name: "First")
        let second = Song(name: "Second")
        let kept = Song(name: "Kept")
        [first, second, kept].forEach(context.insert)

        let setlist = Setlist(name: "Show")
        context.insert(setlist)
        for (index, song) in [first, kept, second].enumerated() {
            let entry = SetlistEntry(sortOrder: index, song: song)
            context.insert(entry)
            setlist.entries.append(entry)
        }
        try context.save()

        try SongLibraryStore.delete([first, second], context: context)

        let remainingSongs = try context.fetch(FetchDescriptor<Song>())
        XCTAssertEqual(remainingSongs.map(\.name), ["Kept"])
        let remainingEntries = try context.fetch(FetchDescriptor<SetlistEntry>())
        XCTAssertEqual(remainingEntries.compactMap { $0.song?.name }, ["Kept"])
        XCTAssertEqual(setlist.entries.count, 1)
    }

    func testDeleteWithNoSongsLeavesLibraryUntouched() throws {
        let context = try makeContext()
        context.insert(Song(name: "Only"))
        try context.save()

        try SongLibraryStore.delete([], context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Song>()).count, 1)
    }

    func testDuplicateNameSkipsTakenCopies() {
        XCTAssertEqual(SongLibraryStore.duplicateName(for: "Song", existingNames: ["Song"]), "Song Copy")
        XCTAssertEqual(
            SongLibraryStore.duplicateName(for: "Song", existingNames: ["Song", "Song Copy", "Song Copy 2"]),
            "Song Copy 3"
        )
    }
}
