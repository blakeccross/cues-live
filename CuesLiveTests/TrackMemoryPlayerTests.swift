import AVFoundation
import os
import XCTest
@testable import CuesLive

/// Drives a track's render path block by block with a deterministic clock.
final class TrackMemoryPlayerTests: XCTestCase {
    private let sampleRate = DecodedStemBuffer.engineSampleRate
    private let blockFrames: AVAudioFrameCount = 512
    private let amplitude: Float = 0.5
    private let seconds = 4.0

    func testFaderChangeWhileStoppedLandsWithoutARampOnPlay() throws {
        let transport = AudioPlaybackTransport()
        let player = try makePlayer(transport: transport)
        player.updateMix(volume: 0.25, pan: 0, isAudible: true)

        transport.beginPlayback(from: 0)
        let block = try renderBlock(player, hostTime: hostTicks(seconds: 100))

        XCTAssertEqual(block[0], amplitude * 0.25, accuracy: 0.000_1, "no ramp down from unity")
        XCTAssertEqual(block[block.count - 1], amplitude * 0.25, accuracy: 0.000_1)
    }

    func testFaderChangeWhilePlayingRampsFromThePreviousGain() throws {
        let transport = AudioPlaybackTransport()
        let player = try makePlayer(transport: transport)
        transport.beginPlayback(from: 0)
        let origin = hostTicks(seconds: 100)
        _ = try renderBlock(player, hostTime: origin)

        player.updateMix(volume: 0.25, pan: 0, isAudible: true)
        let block = try renderBlock(player, hostTime: origin + hostTicks(seconds: blockSeconds))

        XCTAssertEqual(block[0], amplitude, accuracy: 0.000_1, "starts at the previous gain")
        XCTAssertEqual(block[block.count - 1], amplitude * 0.25, accuracy: 0.000_1, "ends on the new gain")
    }

    func testInvalidatedPlayerRendersSilence() throws {
        let transport = AudioPlaybackTransport()
        let player = try makePlayer(transport: transport)
        transport.beginPlayback(from: 0)

        player.invalidateRendering()
        let block = try renderBlock(player, hostTime: hostTicks(seconds: 100))

        XCTAssertEqual(block.max(), 0)
    }

    func testSettingsPublishedDuringRenderingDoNotDisturbTheOutput() throws {
        let undisturbed = try renderSeconds(whileRepublishingSettings: false)
        let republished = try renderSeconds(whileRepublishingSettings: true)

        XCTAssertEqual(republished, undisturbed, "republishing identical settings must not change a sample")
    }

    func testStemAtAnotherSampleRatePlaysContinuouslyAtItsOwnSpeed() throws {
        let sourceRate = 44_100.0
        let period = 44_100
        let frames = Int(seconds * sourceRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = Float(index % period) / Float(period) }
        let stem = try DecodedStemBuffer.monoStem(from: pcm, targetSampleRate: sourceRate)
        let transport = AudioPlaybackTransport()
        transport.setDuration(seconds)
        let player = TrackMemoryPlayer(
            trackID: UUID(),
            buffer: stem,
            transport: transport,
            mapper: .linear(trimStart: 0, trimEnd: seconds)
        )
        transport.beginPlayback(from: 0)

        let origin = hostTicks(seconds: 100)
        var output: [Float] = []
        for block in 0..<40 {
            output += try renderBlock(player, hostTime: origin + hostTicks(seconds: Double(block) * blockSeconds))
        }

        // One output frame at 48 kHz moves 44.1/48 of a source frame through the ramp.
        let step = Float(sourceRate / sampleRate) / Float(period)
        let jumps = zip(output, output.dropFirst()).enumerated().filter { _, pair in
            abs((pair.1 - pair.0) - step) > step * 0.25
        }
        XCTAssertTrue(jumps.isEmpty, "\(jumps.count) discontinuities, first at frames \(jumps.prefix(6).map(\.offset))")
        XCTAssertEqual(output[48_000 / 4], Float(0.25 * sourceRate) / Float(period), accuracy: step * 2, "a quarter second in")
    }

    func testTransposedStemAtAnotherSampleRateLandsOnTheRequestedPitch() throws {
        let sourceRate = 44_100.0
        let frequency = 441.0
        let frames = Int(seconds * sourceRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = Float(sin(2 * .pi * frequency * Double(index) / sourceRate)) * 0.5 }
        let transport = AudioPlaybackTransport()
        transport.setDuration(seconds)
        let player = TrackMemoryPlayer(
            trackID: UUID(),
            buffer: try DecodedStemBuffer.monoStem(from: pcm, targetSampleRate: sourceRate),
            transport: transport,
            mapper: .linear(trimStart: 0, trimEnd: seconds)
        )
        player.setTransposeSemitones(12)
        transport.beginPlayback(from: 0)

        let origin = hostTicks(seconds: 100)
        var output: [Float] = []
        for block in 0..<120 {
            output += try renderBlock(player, hostTime: origin + hostTicks(seconds: Double(block) * blockSeconds))
        }

        // Count rising zero crossings over the last second, past the stretcher's start-up.
        let lastSecond = output.suffix(Int(sampleRate))
        let crossings = zip(lastSecond, lastSecond.dropFirst()).filter { $0.0 < 0 && $0.1 >= 0 }.count
        XCTAssertEqual(Double(crossings), frequency * 2, accuracy: 10, "an octave up, with no extra shift from the rate")
    }

    /// Renders the first three seconds on a background thread, the way the audio thread
    /// does. Optionally the calling thread keeps republishing the same settings meanwhile.
    private func renderSeconds(whileRepublishingSettings republishes: Bool) throws -> [Float] {
        let transport = AudioPlaybackTransport()
        transport.setDuration(seconds)
        let mapper = ArrangementTimelineMapper.linear(trimStart: 0, trimEnd: seconds)
        let player = try makePlayer(transport: transport, mapper: mapper)
        player.updateMix(volume: 0.8, pan: 0, isAudible: true)
        transport.beginPlayback(from: 0)

        let output = OSAllocatedUnfairLock(initialState: [Float]())
        let renderFinished = DispatchGroup()
        renderFinished.enter()
        let origin = hostTicks(seconds: 100)
        let blocks = Int(3 / blockSeconds)
        Thread.detachNewThread { [self] in
            var rendered: [Float] = []
            for block in 0..<blocks {
                let hostTime = origin + hostTicks(seconds: Double(block) * blockSeconds)
                rendered += (try? renderBlock(player, hostTime: hostTime)) ?? []
            }
            let finished = rendered
            output.withLock { $0 = finished }
            renderFinished.leave()
        }

        if republishes {
            while renderFinished.wait(timeout: .now()) == .timedOut {
                player.updateMapper(mapper)
                player.setPlaybackWindow(offset: 0, endTimeline: nil)
                player.setTransposeSemitones(0)
            }
        } else {
            renderFinished.wait()
        }
        return output.withLock { $0 }
    }

    // MARK: - Fixtures

    private var blockSeconds: TimeInterval {
        Double(blockFrames) / sampleRate
    }

    private func hostTicks(seconds: TimeInterval) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return UInt64((seconds * 1_000_000_000 * Double(info.denom) / Double(info.numer)).rounded())
    }

    /// A mono stem holding `amplitude` throughout.
    private func makePlayer(
        transport: AudioPlaybackTransport,
        mapper: ArrangementTimelineMapper? = nil
    ) throws -> TrackMemoryPlayer {
        transport.setDuration(seconds)
        let frames = Int(seconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = amplitude }
        let buffer = try DecodedStemBuffer.monoStem(from: pcm)
        return TrackMemoryPlayer(
            trackID: UUID(),
            buffer: buffer,
            transport: transport,
            mapper: mapper ?? ArrangementTimelineMapper.linear(trimStart: 0, trimEnd: seconds)
        )
    }

    private func renderBlock(_ player: TrackMemoryPlayer, hostTime: UInt64) throws -> [Float] {
        let byteSize = Int(blockFrames) * MemoryLayout<Float>.size
        let storage = UnsafeMutableRawPointer.allocate(byteCount: byteSize, alignment: 16)
        defer { storage.deallocate() }
        let listPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { listPointer.deallocate() }
        listPointer.pointee.mNumberBuffers = 1
        listPointer.pointee.mBuffers = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(byteSize), mData: storage)
        player.renderBlock(frameCount: blockFrames, hostTime: hostTime, outputBuffer: listPointer)
        let floats = storage.bindMemory(to: Float.self, capacity: Int(blockFrames))
        return Array(UnsafeBufferPointer(start: floats, count: Int(blockFrames)))
    }
}
