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

        viewModel.removeEntries([setlist.sortedEntries[1]], from: setlist, context: context)

        XCTAssertEqual(titles(of: setlist), ["A", "C"])
        XCTAssertEqual(setlist.sortedEntries.map(\.sortOrder), [0, 1])
    }

    func testRemoveEntriesRemovesSongsAndHeadersTogether() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)
        viewModel.insertHeader(title: "Set 1", at: 0, to: setlist, context: context)
        insertSongs(["A", "B", "C", "D"], into: setlist, viewModel: viewModel, context: context)

        let entries = setlist.sortedEntries
        viewModel.removeEntries([entries[0], entries[2], entries[4]], from: setlist, context: context)

        XCTAssertEqual(titles(of: setlist), ["A", "C"])
        XCTAssertEqual(setlist.sortedEntries.map(\.sortOrder), [0, 1])
    }

    func testRemoveEntriesIgnoresEntriesFromAnotherSetlist() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)
        let other = makeSetlist(in: context)
        insertSongs(["A", "B"], into: setlist, viewModel: viewModel, context: context)
        insertSongs(["X"], into: other, viewModel: viewModel, context: context)

        viewModel.removeEntries(other.sortedEntries, from: setlist, context: context)

        XCTAssertEqual(titles(of: setlist), ["A", "B"])
        XCTAssertEqual(titles(of: other), ["X"])
    }

    func testMoveEntriesMovesNonContiguousSelectionAsOneBlock() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)
        insertSongs(["A", "B", "C", "D", "E"], into: setlist, viewModel: viewModel, context: context)

        // Drag "A" and "C" below "D" (destination offset 4 = before "E").
        viewModel.moveEntries(in: setlist, from: IndexSet([0, 2]), to: 4, context: context)

        XCTAssertEqual(titles(of: setlist), ["B", "D", "A", "C", "E"])
        XCTAssertEqual(setlist.sortedEntries.map(\.sortOrder), [0, 1, 2, 3, 4])
    }

    func testMoveEntriesBeforeTargetKeepsRelativeOrder() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)
        insertSongs(["A", "B", "C", "D", "E"], into: setlist, viewModel: viewModel, context: context)
        let entries = setlist.sortedEntries

        // Passed out of order; the block keeps setlist order ("B" before "E").
        viewModel.moveEntries([entries[4], entries[1]], before: entries[0], in: setlist, context: context)
        XCTAssertEqual(titles(of: setlist), ["B", "E", "A", "C", "D"])

        viewModel.moveEntries([entries[0], entries[2]], before: nil, in: setlist, context: context)
        XCTAssertEqual(titles(of: setlist), ["B", "E", "D", "A", "C"])
    }

    func testMoveEntriesBeforeMovedTargetUsesNextUnmovedEntry() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)
        insertSongs(["A", "B", "C", "D"], into: setlist, viewModel: viewModel, context: context)
        let entries = setlist.sortedEntries

        viewModel.moveEntries([entries[0], entries[2]], before: entries[2], in: setlist, context: context)

        XCTAssertEqual(titles(of: setlist), ["B", "A", "C", "D"])
    }

    func testMoveEntriesInPlaceKeepsOverlapTransition() throws {
        let context = try makeContext()
        let viewModel = SetlistViewModel()
        let setlist = makeSetlist(in: context)
        insertSongs(["A", "B", "C"], into: setlist, viewModel: viewModel, context: context)
        let entries = setlist.sortedEntries
        viewModel.setOverlapTransition(
            OverlapTransitionConfig(startOffsetSeconds: 4),
            for: entries[0],
            context: context
        )

        // Drop "A" and "B" back where they already are.
        viewModel.moveEntries([entries[0], entries[1]], before: entries[2], in: setlist, context: context)

        XCTAssertEqual(titles(of: setlist), ["A", "B", "C"])
        XCTAssertEqual(entries[0].transition, .overlap)
    }

    private func insertSongs(
        _ names: [String],
        into setlist: Setlist,
        viewModel: SetlistViewModel,
        context: ModelContext
    ) {
        for name in names {
            let song = Song(name: name)
            context.insert(song)
            viewModel.insertSong(song, at: setlist.entries.count, to: setlist, context: context)
        }
    }
}

final class LiveSetlistDurationFormatTests: XCTestCase {
    func testHeaderDurationRoundTripsThroughMinutesAndSeconds() {
        let samples = [0, 36, 5 * 60 + 36, 90 * 60, LiveSetlistDurationFormat.maximumMinutes * 60 + 59]
        for sample in samples {
            let parts = LiveSetlistDurationFormat.components(from: TimeInterval(sample))
            XCTAssertEqual(
                LiveSetlistDurationFormat.seconds(minutes: parts.minutes, seconds: parts.seconds),
                TimeInterval(sample)
            )
        }
    }

    func testFinalCutDigitEntryReadsFromTheRight() {
        XCTAssertEqual(LiveSetlistDurationFormat.seconds(fromFinalCutDigits: "536"), 5 * 60 + 36)
        XCTAssertEqual(LiveSetlistDurationFormat.seconds(fromFinalCutDigits: "5"), 5)
        XCTAssertEqual(LiveSetlistDurationFormat.seconds(fromFinalCutDigits: "300"), 3 * 60)
        XCTAssertEqual(LiveSetlistDurationFormat.seconds(fromFinalCutDigits: "30000"), 3 * 3600)
        XCTAssertEqual(LiveSetlistDurationFormat.seconds(fromFinalCutDigits: "13000"), 3600 + 30 * 60)
        XCTAssertEqual(LiveSetlistDurationFormat.seconds(fromFinalCutDigits: "90"), 90)
        XCTAssertEqual(LiveSetlistDurationFormat.finalCutDisplay(for: 5 * 60 + 36), "00:05:36")
        XCTAssertEqual(LiveSetlistDurationFormat.finalCutDisplay(for: 90), "00:01:30")
        XCTAssertEqual(LiveSetlistDurationFormat.finalCutEntryDisplay(digits: "90"), "00:00:90")
        XCTAssertEqual(LiveSetlistDurationFormat.finalCutEntryDisplay(digits: "536"), "00:05:36")
    }

    func testHeaderDurationClampsMinutesAndSeconds() {
        XCTAssertEqual(LiveSetlistDurationFormat.components(from: -4).minutes, 0)
        XCTAssertEqual(LiveSetlistDurationFormat.components(from: -4).seconds, 0)
        XCTAssertEqual(
            LiveSetlistDurationFormat.seconds(minutes: 5_000, seconds: 80),
            TimeInterval(LiveSetlistDurationFormat.maximumMinutes * 60 + 59)
        )
    }
}
