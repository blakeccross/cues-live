import XCTest
@testable import CuesLive

final class ProceduralClickSourceTests: XCTestCase {
    private func makePattern(onsets: [Int], accents: [Bool]) -> ProceduralClickSource.Pattern {
        ProceduralClickSource.Pattern(
            key: nil,
            events: zip(onsets, accents).map { ProceduralClickSource.Event(frame: $0, isAccent: $1) },
            hits: ProceduralClickSource.Hits(accent: [1, 0.5], normal: [0.25, 0.125])
        )
    }

    private func render(_ source: ProceduralClickSource, from start: Int, count: Int) -> [Float] {
        var output = [Float](repeating: -1, count: count)
        output.withUnsafeMutableBufferPointer { buffer in
            _ = source.copy(
                channel: 0,
                startingFrame: start,
                frameCount: count,
                into: buffer.baseAddress!,
                destinationOffset: 0,
                gain: 1
            )
        }
        return output
    }

    func testTriggersEachClickSampleAtItsOnset() throws {
        let source = try ProceduralClickSource(pattern: makePattern(onsets: [2, 6], accents: [true, false]))

        XCTAssertEqual(render(source, from: 0, count: 9), [0, 0, 1, 0.5, 0, 0, 0.25, 0.125, 0])
    }

    func testClickStartedInPreviousBlockFinishesInNextBlock() throws {
        let source = try ProceduralClickSource(pattern: makePattern(onsets: [3], accents: [true]))

        XCTAssertEqual(render(source, from: 0, count: 4), [0, 0, 0, 1])
        XCTAssertEqual(render(source, from: 4, count: 3), [0.5, 0, 0])
    }

    func testSwappingPatternChangesWhatPlays() throws {
        let source = try ProceduralClickSource(pattern: makePattern(onsets: [0], accents: [true]))
        source.setPattern(.silent)

        XCTAssertEqual(render(source, from: 0, count: 3), [0, 0, 0])
        XCTAssertNil(source.currentPattern.key)
    }

    func testDisabledClickBuildsNoEvents() {
        let pattern = ClickPlaybackSupport.makePattern(
            settings: ClickSettings(isEnabled: false),
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)],
            duration: 4
        )

        XCTAssertTrue(pattern.events.isEmpty)
    }

    func testEnabledClickPlacesEventsOnTheTempoMap() {
        let pattern = ClickPlaybackSupport.makePattern(
            settings: ClickSettings(isEnabled: true, rhythm: .eighth),
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 120)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)],
            duration: 1
        )
        let sampleRate = DecodedStemBuffer.engineSampleRate

        XCTAssertEqual(pattern.events.map(\.frame), [0, 0.25, 0.5, 0.75].map { Int($0 * sampleRate) })
        XCTAssertEqual(pattern.events.map(\.isAccent), [true, false, false, false])
        XCTAssertFalse(pattern.hits.accent.isEmpty)
        XCTAssertFalse(pattern.hits.normal.isEmpty)
    }

    func testRebuiltPatternReusesHitsItIsGiven() {
        let hits = ProceduralClickSource.Hits(accent: [0.75], normal: [0.5])
        let pattern = ClickPlaybackSupport.makePattern(
            settings: ClickSettings(isEnabled: true),
            tempoChanges: [TempoChange(startMeasure: 1, bpm: 90)],
            timeSignatureChanges: [TimeSignatureChange(numerator: 3, denominator: 4, startMeasure: 1)],
            duration: 2,
            hits: hits
        )

        XCTAssertEqual(pattern.hits.accent, [0.75])
        XCTAssertEqual(pattern.hits.normal, [0.5])
        XCTAssertEqual(pattern.events.count, 3)
    }

    func testEverySoundHasBothSamplesInTheAssetCatalog() throws {
        for sound in ClickSound.allCases {
            let hits = try ClickPlaybackSupport.hits(for: ClickSettings(sound: sound))
            XCTAssertFalse(hits.accent.isEmpty, sound.displayName)
            XCTAssertFalse(hits.normal.isEmpty, sound.displayName)
        }
    }

    func testEachHitPlaysAtItsOwnVolumeAndSound() throws {
        var settings = ClickSettings(sound: .standard)
        settings.accentSample = .accent(of: .woodblock)
        settings.accentVolume = 0.5
        settings.beatVolume = 0.25

        let hits = try ClickPlaybackSupport.hits(for: settings)
        let fullAccent = try ClickPlaybackSupport.hits(for: ClickSettings(sound: .woodblock)).accent
        let fullBeat = try ClickPlaybackSupport.hits(for: ClickSettings(sound: .standard)).normal

        XCTAssertEqual(hits.accent, fullAccent.map { $0 * 0.5 })
        XCTAssertEqual(hits.normal, fullBeat.map { $0 * 0.25 })
    }
}
