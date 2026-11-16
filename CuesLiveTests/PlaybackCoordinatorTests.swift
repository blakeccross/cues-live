import SwiftData
import XCTest
@testable import CuesLive

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func overlapSeconds(in items: [LiveSetlistTimelineItem]) -> [TimeInterval?] {
        items.compactMap { item in
            guard case .song(_, _, _, let overlapSeconds) = item else { return nil }
            return overlapSeconds
        }
    }

    func testTimelineCarriesOverlapLengthIntoNextSong() throws {
        let context = try makeContext()
        let setlist = Setlist(name: "Test")
        context.insert(setlist)
        let transitions: [SetlistTransition] = [.overlap, .continue, .overlap]
        for (index, transition) in transitions.enumerated() {
            let song = Song(name: "Song \(index)")
            context.insert(song)
            let entry = SetlistEntry(sortOrder: index, song: song, transition: transition)
            if transition == .overlap {
                entry.overlapConfig = OverlapTransitionConfig(startOffsetSeconds: 4)
            }
            setlist.entries.append(entry)
        }

        let coordinator = PlaybackCoordinator()
        coordinator.updateTransitions(from: setlist)

        // The last song has no next song, so its overlap is dropped along with its transition.
        XCTAssertEqual(overlapSeconds(in: coordinator.timelineItems), [4, nil, nil])
    }

    func testTimelineCarriesHeaderTime() throws {
        let context = try makeContext()
        let setlist = Setlist(name: "Test")
        context.insert(setlist)
        setlist.entries.append(SetlistEntry(sortOrder: 0, headerTitle: "Announcements", headerTimeSeconds: 300))
        setlist.entries.append(SetlistEntry(sortOrder: 1, headerTitle: "Set 2"))

        let coordinator = PlaybackCoordinator()
        coordinator.updateTransitions(from: setlist)

        let headers = coordinator.timelineItems.compactMap { item -> String? in
            guard case .header(_, let title, let timeSeconds) = item else { return nil }
            return "\(title) \(timeSeconds.map { String(Int($0)) } ?? "-")"
        }
        XCTAssertEqual(headers, ["Announcements 300", "Set 2 -"])
    }
}
