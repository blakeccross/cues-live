import XCTest
@testable import CuesLive

final class ClickSettingsTests: XCTestCase {
    func testProjectWrittenBeforeClickDecodesWithClickOff() throws {
        let metadata = try JSONDecoder().decode(
            SongProjectMetadata.self,
            from: Data(#"{"transposeSemitones":0,"smartGuideEnabled":false}"#.utf8)
        )

        XCTAssertEqual(metadata.click, ClickSettings())
        XCTAssertFalse(metadata.click.isEnabled)
        XCTAssertEqual(metadata.click.rhythm, .auto)
    }

    func testUnknownRhythmAndSoundFallBackToDefaults() throws {
        let settings = try JSONDecoder().decode(
            ClickSettings.self,
            from: Data(#"{"isEnabled":true,"rhythm":"dottedQuarter","sound":"theremin"}"#.utf8)
        )

        XCTAssertEqual(settings, ClickSettings(isEnabled: true, rhythm: .auto, sound: .standard))
    }

    func testClickSettingsRoundTripThroughProjectMetadata() throws {
        let song = Song(name: "Test")
        song.clickSettings = ClickSettings(isEnabled: true, rhythm: .sixteenth)

        let data = try JSONEncoder().encode(SongProjectMetadata(from: song))
        let decoded = try JSONDecoder().decode(SongProjectMetadata.self, from: data)
        let restored = Song(name: "Restored")
        decoded.apply(to: restored)

        XCTAssertEqual(restored.clickSettings, ClickSettings(isEnabled: true, rhythm: .sixteenth))
    }
}
