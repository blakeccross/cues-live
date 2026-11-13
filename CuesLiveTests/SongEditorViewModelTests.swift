import SwiftData
import XCTest
@testable import CuesLive

@MainActor
final class SongEditorViewModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    override func tearDown() {
        AudioEngineManager.shared.onPlaybackFinished = nil
        super.tearDown()
    }

    func testFollowingSetlistLoadLeavesEngineToSetlist() throws {
        let context = try makeContext()
        let song = Song(name: "Live")
        context.insert(song)
        var setlistHandlerCalls = 0
        AudioEngineManager.shared.onPlaybackFinished = { setlistHandlerCalls += 1 }

        let viewModel = SongEditorViewModel(song: song, followingSetlist: PlaybackCoordinator())
        viewModel.loadSong(context: context)

        XCTAssertTrue(viewModel.followsSetlist)
        XCTAssertTrue(viewModel.isLoaded)
        XCTAssertNil(viewModel.loadError)
        // A standalone editor clears this callback to take the engine from the setlist.
        AudioEngineManager.shared.onPlaybackFinished?()
        XCTAssertEqual(setlistHandlerCalls, 1)
    }

    func testStandaloneLoadClaimsEngine() throws {
        let context = try makeContext()
        let song = Song(name: "Solo")
        context.insert(song)
        AudioEngineManager.shared.onPlaybackFinished = {}

        let viewModel = SongEditorViewModel(song: song)
        viewModel.loadSong(context: context)

        XCTAssertFalse(viewModel.followsSetlist)
        XCTAssertNil(AudioEngineManager.shared.onPlaybackFinished)
    }

    func testFollowingSetlistIgnoresEditsWhenSongIsNotLoaded() throws {
        let context = try makeContext()
        let song = Song(name: "Not Loaded")
        context.insert(song)
        let coordinator = PlaybackCoordinator()
        XCTAssertFalse(coordinator.hasLoadedSong(song.id))

        let engine = coordinator.playbackEngine
        let durationBefore = engine.duration
        let viewModel = SongEditorViewModel(song: song, followingSetlist: coordinator)
        viewModel.loadSong(context: context)
        XCTAssertTrue(viewModel.isLoaded)

        var timeline = SongTimeline()
        timeline.clips = [TrackClip(trackID: UUID(), timelineStartSeconds: 0, duration: durationBefore + 60, sourceStartSeconds: 0)]
        viewModel.syncArrangement(timeline)
        viewModel.syncTempoMap([TempoChange(startMeasure: 1, bpm: 200)], timeSignatureChanges: [])

        XCTAssertEqual(engine.duration, durationBefore)
    }
}
