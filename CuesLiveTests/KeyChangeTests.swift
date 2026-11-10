import XCTest
@testable import CuesLive

final class KeyChangeTests: XCTestCase {
    func testDisplayedKeyWrapsSemitones() {
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "Bb", transposeSemitones: 2), "C")
        XCTAssertEqual(SongMusicalKey.display(baseRaw: "C", transposeSemitones: -1), "B")
        XCTAssertNil(SongMusicalKey.display(baseRaw: nil, transposeSemitones: 3))
        XCTAssertEqual(SongMusicalKey.transportText(baseRaw: nil, transposeSemitones: 2), "—")
    }

    func testDefaultSelectionLeavesUtilityTracksOff() {
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Kick", groupName: "Drums"))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Shaker", groupName: "Percussion"))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Click", groupName: "Click"))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "Click", groupName: nil))
        XCTAssertFalse(KeyChangeTrackSelection.includesByDefault(displayName: "LTC", groupName: "Timecode"))
        XCTAssertTrue(KeyChangeTrackSelection.includesByDefault(displayName: "Bass", groupName: "Bass"))
        XCTAssertTrue(KeyChangeTrackSelection.includesByDefault(displayName: "Vocal", groupName: nil))
    }

    func testOldMetadataDecodesWithoutTranspose() throws {
        let json = """
        {"baseKeyRaw":"G","smartGuideEnabled":false}
        """.data(using: .utf8)!
        let metadata = try JSONDecoder().decode(SongProjectMetadata.self, from: json)
        XCTAssertEqual(metadata.transposeSemitones, 0)
        XCTAssertEqual(metadata.baseKeyRaw, "G")
    }

    func testPitchShiftPreservesLengthAndRaisesAnOctave() throws {
        let sampleRate = 48_000.0
        let frameCount = 48_000
        let source = try DecodedStemBuffer.silent(frameCount: frameCount, sampleRate: sampleRate)
        source.withMutableSamples(channel: 0) { samples, count in
            for index in 0..<count {
                let phase = 2 * Double.pi * 440 * Double(index) / sampleRate
                samples[index] = Float(sin(phase))
            }
        }

        let shifted = try PitchShifter.shift(source, semitones: 12)
        XCTAssertEqual(shifted.frameCount, frameCount)

        var output = [Float](repeating: 0, count: frameCount)
        shifted.withMutableSamples(channel: 0) { samples, count in
            output.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(from: samples, count: count)
            }
        }

        let fundamental = magnitude(of: output, sampleRate: sampleRate, frequency: 440)
        let octave = magnitude(of: output, sampleRate: sampleRate, frequency: 880)
        XCTAssertGreaterThan(octave, fundamental * 4)
    }

    private func magnitude(of samples: [Float], sampleRate: Double, frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        var real = 0.0
        var imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let angle = omega * Double(index)
            real += Double(sample) * cos(angle)
            imaginary -= Double(sample) * sin(angle)
        }
        return (real * real + imaginary * imaginary).squareRoot()
    }
}
