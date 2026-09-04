import AVFoundation
import XCTest
@testable import CuesLive

/// `StreamingStemBuffer` keeps a sliding window of pages around the playhead and
/// evicts everything else, which assumes playback only ever moves forward. A
/// section loop breaks that assumption: when playback wraps, the loop head has
/// long since been evicted and the render thread reads silence.
final class StreamingStemBufferLoopTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let fileSeconds = 20.0
    private let sampleValue: Float = 0.5

    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loop-\(UUID().uuidString).caf")
        try writeConstantToneFile(at: fileURL)
    }

    override func tearDownWithError() throws {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        try super.tearDownWithError()
    }

    func testLoopHeadIsEvictedWithoutPinning() throws {
        let buffer = try StreamingStemBuffer(url: fileURL)
        buffer.prewarm(aroundSourceFrame: 0)
        XCTAssertEqual(readFirstSample(from: buffer, at: 0), sampleValue, accuracy: 0.0001)

        playTowardEndOfFile(buffer)

        // Reproduces the missing downbeat. Read exactly once: a read re-centers the
        // reader window, so polling here would page the loop head back in.
        XCTAssertEqual(
            readFirstSample(from: buffer, at: 0),
            0,
            accuracy: 0.0001,
            "loop head should have been evicted once the playhead moved away"
        )
    }

    func testPinnedLoopHeadSurvivesPlaybackMovingAway() throws {
        let buffer = try StreamingStemBuffer(url: fileURL)
        buffer.prewarm(aroundSourceFrame: 0)
        buffer.setPinnedRegion(sourceFrames: 0..<Int(2 * sampleRate))

        playTowardEndOfFile(buffer)

        XCTAssertEqual(
            readFirstSample(from: buffer, at: 0),
            sampleValue,
            accuracy: 0.0001,
            "a pinned loop head must stay resident so the first frames after a wrap are audible"
        )
    }

    func testClearingThePinnedRegionAllowsEvictionAgain() throws {
        let buffer = try StreamingStemBuffer(url: fileURL)
        buffer.prewarm(aroundSourceFrame: 0)
        buffer.setPinnedRegion(sourceFrames: 0..<Int(2 * sampleRate))
        playTowardEndOfFile(buffer)
        XCTAssertEqual(readFirstSample(from: buffer, at: 0), sampleValue, accuracy: 0.0001)

        buffer.setPinnedRegion(sourceFrames: nil)
        playTowardEndOfFile(buffer)

        XCTAssertEqual(
            readFirstSample(from: buffer, at: 0),
            0,
            accuracy: 0.0001,
            "unpinning should return the page to the normal sliding window"
        )
    }

    /// Mimics the render thread reading near the end of the file, which is what
    /// moves the reader's window and evicts the pages behind it. The reader polls
    /// every 40ms, so this drives it for many times that.
    private func playTowardEndOfFile(_ buffer: StreamingStemBuffer) {
        buffer.setReaderActive(true)
        let target = Int((fileSeconds - 1) * sampleRate)
        for _ in 0..<10 {
            _ = readFirstSample(from: buffer, at: target)
            Thread.sleep(forTimeInterval: 0.05)
        }
        buffer.setReaderActive(false)
    }

    private func readFirstSample(from buffer: StreamingStemBuffer, at frame: Int) -> Float {
        var destination = [Float](repeating: 0, count: 64)
        destination.withUnsafeMutableBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            _ = buffer.copy(
                channel: 0,
                startingFrame: frame,
                frameCount: pointer.count,
                into: base,
                destinationOffset: 0,
                gain: 1
            )
        }
        return destination[0]
    }

    private func writeConstantToneFile(at url: URL) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let chunkFrames = AVAudioFrameCount(48_000)
        let chunk = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
        )
        let channel = try XCTUnwrap(chunk.floatChannelData)

        chunk.frameLength = chunkFrames
        for frame in 0..<Int(chunkFrames) {
            channel[0][frame] = sampleValue
        }

        for _ in 0..<Int(fileSeconds) {
            try file.write(from: chunk)
        }
    }
}
