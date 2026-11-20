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

    func testProjectWrittenBeforeAccentAndBeatUsesItsSoundForBoth() throws {
        let settings = try JSONDecoder().decode(
            ClickSettings.self,
            from: Data(#"{"isEnabled":true,"rhythm":"auto","sound":"woodblock"}"#.utf8)
        )

        XCTAssertEqual(settings.accentSample, .accent(of: .woodblock))
        XCTAssertEqual(settings.beatSample, .normal(of: .woodblock))
        XCTAssertEqual(settings.accentVolume, 1)
        XCTAssertEqual(settings.beatVolume, 1)
        XCTAssertFalse(settings.isCustomized)
    }

    func testAccentAndBeatRoundTripAndKeepTheLegacySoundKey() throws {
        var settings = ClickSettings(isEnabled: true)
        settings.accentSample = .accent(of: .woodblock)
        settings.beatSample = .normal(of: .beep)
        settings.accentVolume = 0.8
        settings.beatVolume = 0.4

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ClickSettings.self, from: data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded, settings)
        // Older versions read only "sound"; they get the beat sound, which most clicks use.
        XCTAssertEqual(json["sound"] as? String, "beep")
    }

    func testStoredVolumesAreClampedAndMissingMeansFull() {
        XCTAssertEqual(ClickSettings.volume(nil), 1)
        XCTAssertEqual(ClickSettings.volume(1.5), 1)
        XCTAssertEqual(ClickSettings.volume(-0.2), 0)
        XCTAssertEqual(ClickSettings.volume(.nan), 1)
        XCTAssertEqual(ClickSettings.volume(0.3), 0.3)
    }

    func testSharedSoundSetsBothAndReadsNilWhenTheyDiffer() {
        var settings = ClickSettings()
        settings.sound = .beep
        XCTAssertEqual(settings.accentSample, .accent(of: .beep))
        XCTAssertEqual(settings.beatSample, .normal(of: .beep))

        settings.accentSample = .accent(of: .woodblock)
        XCTAssertNil(settings.sound)
        XCTAssertTrue(settings.isCustomized)
    }

    func testLowerVolumeCountsAsCustomizedAndNeedsNewHits() {
        var quieter = ClickSettings()
        quieter.beatVolume = 0.5

        XCTAssertTrue(quieter.isCustomized)
        XCTAssertFalse(quieter.hasSameHits(as: ClickSettings()))
        XCTAssertTrue(ClickSettings(rhythm: .eighth).hasSameHits(as: ClickSettings()))
    }

    func testSongStoresAccentAndBeatSettings() {
        var settings = ClickSettings(isEnabled: true)
        settings.accentSample = .normal(of: .woodblock)
        settings.accentVolume = 0.6
        settings.beatVolume = 0.9
        let song = Song(name: "Test")

        song.clickSettings = settings

        XCTAssertEqual(song.clickSettings, settings)
    }

    func testSongSavedBeforeAccentAndBeatUsesItsSoundForBoth() {
        let song = Song(name: "Test")
        song.clickSoundRaw = ClickSound.beep.rawValue

        XCTAssertEqual(song.clickSettings, ClickSettings(sound: .beep))
    }
}
