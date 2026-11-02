import AVFoundation
import XCTest
@testable import CuesLive

final class WaveformLoaderTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDown() {
        tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        tempURLs = []
        super.tearDown()
    }

    /// Writes a mono file whose amplitude steps up each second: 0.1, 0.2, ... so peaks are predictable.
    private func makeSteppedFile(seconds: Int, sampleRate: Double = 44_100) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        tempURLs.append(url)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let framesPerSecond = Int(sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerSecond)))
        buffer.frameLength = AVAudioFrameCount(framesPerSecond)

        for second in 0..<seconds {
            let amplitude = Float(second + 1) / Float(seconds)
            let data = try XCTUnwrap(buffer.floatChannelData)[0]
            for frame in 0..<framesPerSecond {
                data[frame] = frame.isMultiple(of: 2) ? amplitude : -amplitude
            }
            try file.write(from: buffer)
        }
        return url
    }

    func testPeakCountScalesWithDuration() {
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 10), 1024)
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 60), 6000)
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 120), 12_000)
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 3600), WaveformLoader.maximumSampleCount)
    }

    func testDecodedPeaksFollowAmplitude() throws {
        let url = try makeSteppedFile(seconds: 20)
        let peaks = WaveformLoader.loadPeaks(from: url)

        XCTAssertEqual(peaks.count, WaveformLoader.overviewSampleCount(forDuration: 20))
        XCTAssertEqual(peaks.max() ?? 0, 1, accuracy: 0.001)
        // Middle of second 5 (amplitude 6/20) normalized by the loudest second.
        let middle = peaks[Int(Double(peaks.count) * 5.5 / 20)]
        XCTAssertEqual(middle, 6.0 / 20.0, accuracy: 0.02)
    }

    func testRefineMatchesFullDecodeAndReportsProgress() throws {
        let url = try makeSteppedFile(seconds: 30)
        let preview = try XCTUnwrap(WaveformLoader.loadPreview(from: url))
        let sketch = preview.sketch()

        XCTAssertEqual(sketch.count, preview.sampleCount)
        XCTAssertGreaterThan(sketch.max() ?? 0, 0.9)

        let refined = WaveformLoader.refinePeaks(from: url, preview: preview) { partial in
            XCTAssertEqual(partial.count, preview.sampleCount)
        }
        XCTAssertEqual(refined, WaveformLoader.loadPeaks(from: url))
    }
}
