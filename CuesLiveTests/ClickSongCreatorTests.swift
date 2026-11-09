import SwiftData
import XCTest
@testable import CuesLive

final class ClickSongCreatorTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testDurationForEightBarsAt120FourFour() {
        let tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        let timeSignatures = [
            TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)
        ]

        let duration = ClickSongCreator.durationForBars(
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatures
        )

        // 8 bars × 4 beats × 0.5s = 16s
        XCTAssertEqual(duration, 16, accuracy: 0.0001)
        XCTAssertEqual(ClickSongCreator.barCount, 8)
    }

    func testDurationForEightBarsAt120ThreeFour() {
        let tempoChanges = [TempoChange(startMeasure: 1, bpm: 120)]
        let timeSignatures = [
            TimeSignatureChange(numerator: 3, denominator: 4, startMeasure: 1)
        ]

        let duration = ClickSongCreator.durationForBars(
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatures
        )

        // 8 bars × 3 beats × 0.5s = 12s
        XCTAssertEqual(duration, 12, accuracy: 0.0001)
    }

    func testCreateSetsTempoMeterClickAndLoopSection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var createdSong: Song?

        defer {
            if let song = createdSong {
                cleanupProjectFiles(for: song)
                context.delete(song)
                try? context.save()
            }
        }

        let song = try ClickSongCreator.create(
            name: "Click Loop Test",
            bpm: 120,
            numerator: 4,
            denominator: 4,
            context: context
        )
        createdSong = song

        XCTAssertEqual(song.bpm, 120)
        XCTAssertEqual(song.timeSignatureNumerator, 4)
        XCTAssertEqual(song.timeSignatureDenominator, 4)

        let click = ClickTrackFileGenerator.existingClickTrack(in: song)
        XCTAssertNotNil(click)
        XCTAssertEqual(click?.trimEndSeconds ?? 0, 16, accuracy: 0.01)

        let state = try SongProjectBridge.loadProjectState(for: song)
        XCTAssertEqual(state.markers.count, 1)
        XCTAssertEqual(state.markers.first?.name, ClickSongCreator.sectionName)
        XCTAssertEqual(state.markers.first?.loops, true)
        XCTAssertEqual(state.timeline.clips(forTrack: click!.id).count, 1)
        XCTAssertEqual(state.timeline.clips(forTrack: click!.id).first?.duration ?? 0, 16, accuracy: 0.01)
        XCTAssertEqual(state.tempoChanges.referenceBPM, 120, accuracy: 0.001)
        XCTAssertEqual(state.timeSignatureChanges.first?.numerator, 4)
        XCTAssertEqual(state.timeSignatureChanges.first?.denominator, 4)
    }

    func testCreateRejectsEmptyName() {
        let container = try? makeContainer()
        let context = ModelContext(container!)

        XCTAssertThrowsError(
            try ClickSongCreator.create(
                name: "   ",
                bpm: 120,
                numerator: 4,
                denominator: 4,
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? ClickSongCreatorError, .emptyName)
        }
    }

    private func cleanupProjectFiles(for song: Song) {
        guard let projectURL = SongProjectBridge.projectURL(for: song) else { return }
        let projectDirectory = projectURL.deletingLastPathComponent()
        let stemsDirectory = projectDirectory
            .appendingPathComponent("Stems", isDirectory: true)
        try? FileManager.default.removeItem(at: projectURL)
        // Remove stem folder for this song if empty-ish; best-effort cleanup.
        let songStemFolder = stemsDirectory.appendingPathComponent(song.name, isDirectory: true)
        try? FileManager.default.removeItem(at: songStemFolder)
    }
}
