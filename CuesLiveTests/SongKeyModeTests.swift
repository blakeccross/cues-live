import XCTest
@testable import CuesLive

final class SongKeyModeTests: XCTestCase {
    func testMinorKeyLabelTransposesWithMode() {
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "A", modeRaw: "minor"), "Am")
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "A", modeRaw: "minor", transposeSemitones: 3), "Cm")
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "G", modeRaw: nil), "G")
        XCTAssertEqual(SongMusicalKey.transportText(baseRaw: nil, modeRaw: "minor"), "—")
    }

    func testMissingOrUnknownModeReadsAsMajor() {
        XCTAssertEqual(SongKeyMode(raw: nil), .major)
        XCTAssertEqual(SongKeyMode(raw: "dorian"), .major)
        XCTAssertNil(SongKeyMode.major.storedRaw)
        XCTAssertEqual(SongKeyMode.minor.storedRaw, "minor")
    }

    func testMetadataRoundTripsKeyMode() throws {
        let song = Song(name: "Test")
        song.baseKeyRaw = "E"
        song.keyModeRaw = SongKeyMode.minor.storedRaw
        let data = try JSONEncoder().encode(SongProjectMetadata(from: song))
        let decoded = try JSONDecoder().decode(SongProjectMetadata.self, from: data)
        XCTAssertEqual(decoded.keyModeRaw, "minor")
    }

    func testKeyDetectionSkipsRhythmAndUtilityStems() {
        let urls = ["Kick In.wav", "Drums.wav", "Click.wav", "LTC.wav", "Guide.wav", "Bass.wav", "Keys 1.wav", "Custom Pad.wav"]
            .map { URL(fileURLWithPath: "/tmp/song/\($0)") }
        let names = SongKeyDetector.harmonicStems(in: urls).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Bass.wav", "Keys 1.wav", "Custom Pad.wav"])
    }

    func testKeyDetectionFallsBackToAllStemsWhenNoneAreHarmonic() {
        let urls = [URL(fileURLWithPath: "/tmp/song/Drums.wav")]
        XCTAssertEqual(SongKeyDetector.harmonicStems(in: urls), urls)
    }
}
