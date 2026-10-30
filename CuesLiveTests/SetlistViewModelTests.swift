import SwiftData
import XCTest
@testable import CuesLive

@MainActor
final class SetlistViewModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// Points the show file at a temp path so persisting doesn't write into the real show folder.
    private func makeSetlist(in context: ModelContext) -> Setlist {
        let setlist = Setlist(name: "Test \(UUID().uuidString)")
        setlist.showFilePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).cueshow").path
        context.insert(setlist)
        return setlist
    }

    private func titles(of setlist: Setlist) -> [String] {
        setlist.sortedEntries.map { $0.song?.name ?? $0.headerTitle ?? "?" }
    }

    func testMoveEntriesReordersSongsAndHeaders() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)

        viewModel.insertHeader(title: "Set 1", at: 0, to: setlist, context: context)
        for name in ["A", "B", "C"] {
            let song = Song(name: name)
            context.insert(song)
            viewModel.insertSong(song, at: setlist.entries.count, to: setlist, context: context)
        }
        XCTAssertEqual(titles(of: setlist), ["Set 1", "A", "B", "C"])

        // Drag "C" (offset 3) above "A" (destination 1).
        viewModel.moveEntries(in: setlist, from: IndexSet(integer: 3), to: 1, context: context)

        XCTAssertEqual(titles(of: setlist), ["Set 1", "C", "A", "B"])
        XCTAssertEqual(setlist.sortedEntries.map(\.sortOrder), [0, 1, 2, 3])
    }

    func testMoveEntriesResetsMovedOverlapTransitionToContinue() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)

        for name in ["A", "B", "C"] {
            let song = Song(name: name)
            context.insert(song)
            viewModel.insertSong(song, at: setlist.entries.count, to: setlist, context: context)
        }
        let entries = setlist.sortedEntries
        viewModel.setOverlapTransition(
            OverlapTransitionConfig(startOffsetSeconds: 4),
            for: entries[0],
            context: context
        )
        viewModel.setTransition(.stop, for: entries[1], context: context)

        // Move "A" (the overlap entry) to the end.
        viewModel.moveEntries(in: setlist, from: IndexSet(integer: 0), to: 3, context: context)

        XCTAssertEqual(titles(of: setlist), ["B", "C", "A"])
        XCTAssertEqual(entries[0].transition, .continue)
        XCTAssertNil(entries[0].overlapStartOffsetSeconds)
        XCTAssertEqual(entries[1].transition, .stop, "Unmoved entries keep their transition")
    }

    func testRemoveEntryRenumbersSortOrder() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)

        for name in ["A", "B", "C"] {
            let song = Song(name: name)
            context.insert(song)
            viewModel.insertSong(song, at: setlist.entries.count, to: setlist, context: context)
        }

        viewModel.removeEntry(setlist.sortedEntries[1], from: setlist, context: context)

        XCTAssertEqual(titles(of: setlist), ["A", "C"])
        XCTAssertEqual(setlist.sortedEntries.map(\.sortOrder), [0, 1])
    }
}
