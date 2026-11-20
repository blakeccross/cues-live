import XCTest
@testable import CuesLive

final class ClickSampleTests: XCTestCase {
    func testOffersEverySoundsNormalAndAccentSample() {
        XCTAssertEqual(ClickSample.allCases.map(\.displayName), [
            "Default", "Default (Accent)",
            "Woodblock", "Woodblock (Accent)",
            "Beep", "Beep (Accent)"
        ])
    }

    func testSavedValuesRoundTrip() {
        for sample in ClickSample.allCases {
            XCTAssertEqual(ClickSample(rawValue: sample.rawValue), sample)
        }
        XCTAssertEqual(ClickSample.accent(of: .standard).rawValue, "default-accent")
        XCTAssertEqual(ClickSample.normal(of: .woodblock).rawValue, "woodblock")
        XCTAssertNil(ClickSample(rawValue: "cowbell"))
    }

    func testEachSampleNamesItsAsset() {
        XCTAssertEqual(ClickSample.accent(of: .beep).assetName, ClickSound.beep.accentAssetName)
        XCTAssertEqual(ClickSample.normal(of: .beep).assetName, ClickSound.beep.normalAssetName)
    }

    func testSwappedSamplesAreCustomAndPlayAsChosen() throws {
        var settings = ClickSettings(sound: .woodblock)
        settings.accentSample = .normal(of: .woodblock)
        settings.beatSample = .accent(of: .woodblock)

        let hits = try ClickPlaybackSupport.hits(for: settings)
        let pair = try ClickPlaybackSupport.hits(for: ClickSettings(sound: .woodblock))

        XCTAssertNil(settings.sound)
        XCTAssertEqual(hits.accent, pair.normal)
        XCTAssertEqual(hits.normal, pair.accent)
    }

    func testUnknownSampleInAFileFallsBackToTheSoundsPair() throws {
        let settings = try JSONDecoder().decode(
            ClickSettings.self,
            from: Data(#"{"sound":"beep","accentSample":"cowbell-accent","beatSample":"beep"}"#.utf8)
        )

        XCTAssertEqual(settings.accentSample, .accent(of: .beep))
        XCTAssertEqual(settings.beatSample, .normal(of: .beep))
    }
}
