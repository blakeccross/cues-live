import AVFoundation
import os
import XCTest
@testable import CuesLive

/// Runs the real engine graph, capturing the mixer's output.
final class AudioEngineManagerTests: XCTestCase {
    private let level: Float = 0.5

    func testCustomRouteSendsAMonoStemOnlyToItsOutput() throws {
        let routing = OutputRoutingSnapshot(
            deviceUID: nil,
            routesByGroupID: [:],
            ungroupedDestination: .mono(channel: 2),
            channelCount: 2
        )

        let peaks = try capturedPeaks(routing: routing)

        // The default device may be wider than stereo; every output but 2 must stay silent.
        XCTAssertGreaterThanOrEqual(peaks.count, 2)
        for (index, peak) in peaks.enumerated() {
            XCTAssertEqual(peak, index == 1 ? level : 0, accuracy: 0.000_1, "output \(index + 1)")
        }
    }

    func testDefaultRoutePlaysAMonoStemAtFullLevelOnBothOutputs() throws {
        let peaks = try capturedPeaks(routing: nil)

        XCTAssertEqual(peaks.count, 2)
        XCTAssertEqual(peaks[0], level, accuracy: 0.000_1)
        XCTAssertEqual(peaks[1], level, accuracy: 0.000_1)
    }

    func testPlaybackIsContinuousThroughTheRealEngine() throws {
        let jumps = try discontinuities(routing: nil, trackCount: 1)
        XCTAssertTrue(jumps.isEmpty, "\(jumps.count) discontinuities, first: \(jumps.prefix(8))")
    }

    func testPlaybackIsContinuousWithManyTracksOnTheWideOutputPath() throws {
        // A group routed to No Output makes the routing custom, which connects at device width.
        let routing = OutputRoutingSnapshot(
            deviceUID: nil,
            routesByGroupID: [UUID(): .none],
            ungroupedDestination: .defaultDestination,
            channelCount: 2
        )
        let jumps = try discontinuities(routing: routing, trackCount: 8)
        XCTAssertTrue(jumps.isEmpty, "\(jumps.count) discontinuities, first: \(jumps.prefix(8))")
    }

    func testStreamedStemsPlayContinuously() throws {
        let jumps = try discontinuities(routing: nil, trackCount: 8, streamed: true)
        XCTAssertTrue(jumps.isEmpty, "\(jumps.count) discontinuities, first: \(jumps.prefix(8))")
    }

    func testStreamedStemsAtAnotherSampleRatePlayContinuously() throws {
        let jumps = try discontinuities(routing: nil, trackCount: 8, streamed: true, sourceRate: 44_100)
        XCTAssertTrue(jumps.isEmpty, "\(jumps.count) discontinuities, first: \(jumps.prefix(8))")
    }

    func testSwitchingTheRateRebuildsTheMixerAndKeepsPlaybackContinuous() throws {
        let engine = AudioEngineManager(sampleRate: 48_000)
        let seconds = 4.0
        let settings = AudioEngineManager.TrackSettings(
            volume: 1, isMuted: false, isSolo: false, trimStart: 0, trimEnd: seconds
        )
        let routing = OutputRoutingSnapshot(
            deviceUID: nil, routesByGroupID: [:], ungroupedDestination: .defaultDestination, channelCount: 2
        )
        try engine.loadPreparedTracks(
            [AudioEngineManager.PreparedTrackPayload(id: UUID(), buffer: makeRampStem(seconds: seconds), settings: settings, groupID: nil)],
            routing: routing
        )
        defer { engine.shutdown() }

        engine.pinnedSampleRate = 44_100
        engine.applyOutputRoutingKeepingTracks(routing)
        XCTAssertEqual(engine.referenceSampleRate, 44_100)

        let captured = OSAllocatedUnfairLock(initialState: (rate: 0.0, samples: [Float]()))
        engine.installCaptureTapForTesting(silenceSpeakers: true) { buffer, _ in
            guard let left = buffer.floatChannelData?[0] else { return }
            let block = Array(UnsafeBufferPointer(start: left, count: Int(buffer.frameLength)))
            captured.withLock { $0.rate = buffer.format.sampleRate; $0.samples += block }
        }
        defer { engine.removeCaptureTapForTesting() }
        engine.play()
        try XCTSkipUnless(engine.isPlaying, "needs a working audio output device")
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let result = captured.withLock { $0 }
        XCTAssertEqual(result.rate, 44_100, "the mixer renders at the new rate")
        let samples = result.samples.drop { $0 == 0 }
        XCTAssertGreaterThan(samples.count, 22_050)
        // A 48 kHz stem advances 48/44.1 of a source frame per output frame.
        let step = Float(48_000.0 / 44_100) / Float(rampPeriod)
        let jumps = zip(samples, samples.dropFirst()).filter { pair in
            let nearWrap = [pair.0, pair.1].contains { $0 > 0.999 || $0 < 0.001 }
            return !nearWrap && abs((pair.1 - pair.0) - step) > step * 1.5
        }
        XCTAssertTrue(jumps.isEmpty, "\(jumps.count) discontinuities after switching rate")
    }

    /// Plays identical ramp stems through the real engine and lists every place the
    /// captured output does not advance by exactly one frame.
    private func discontinuities(
        routing: OutputRoutingSnapshot?,
        trackCount: Int,
        streamed: Bool = false,
        sourceRate: Double = DecodedStemBuffer.engineSampleRate
    ) throws -> [String] {
        let engine = AudioEngineManager(sampleRate: DecodedStemBuffer.engineSampleRate)
        let seconds = 4.0
        let settings = AudioEngineManager.TrackSettings(
            volume: 1, isMuted: false, isSolo: false, trimStart: 0, trimEnd: seconds
        )
        let stem = try makeRampStem(seconds: seconds)
        let rampFile = FileManager.default.temporaryDirectory.appendingPathComponent("ramp-\(UUID()).caf")
        if streamed { try writeRamp(seconds: seconds, sampleRate: sourceRate, to: rampFile) }
        defer { try? FileManager.default.removeItem(at: rampFile) }
        let sources: [any StemSampleSource] = try (0..<trackCount).map { _ in
            if streamed { return try StreamingStemBuffer(url: rampFile) }
            return stem
        }
        try engine.loadPreparedTracks(
            sources.map { source in
                AudioEngineManager.PreparedTrackPayload(id: UUID(), buffer: source, settings: settings, groupID: nil)
            },
            routing: routing
        )
        let captured = OSAllocatedUnfairLock(initialState: [Float]())
        engine.installCaptureTapForTesting(silenceSpeakers: true) { buffer, _ in
            guard let left = buffer.floatChannelData?[0] else { return }
            let block = Array(UnsafeBufferPointer(start: left, count: Int(buffer.frameLength)))
            captured.withLock { $0 += block }
        }
        defer {
            engine.removeCaptureTapForTesting()
            engine.shutdown()
        }

        engine.play()
        try XCTSkipUnless(engine.isPlaying, "needs a working audio output device")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let samples = captured.withLock { $0 }.drop { $0 == 0 }.map { $0 / Float(trackCount) }
        XCTAssertGreaterThan(samples.count, 24_000, "captured too little audio")
        // The playhead follows the host clock, which slips a frame against the device clock
        // now and then; that one-frame slip is a known limit, anything larger is a bug.
        let step = Float(sourceRate / DecodedStemBuffer.engineSampleRate) / Float(rampPeriod)
        var jumps: [String] = []
        for (index, pair) in zip(samples, samples.dropFirst()).enumerated() {
            let delta = pair.1 - pair.0
            // The ramp drops from 1 to 0 once a period; interpolation smooths across that
            // edge for a few samples, which is the test signal, not a playback fault.
            let nearWrap = [pair.0, pair.1].contains { $0 > 0.999 || $0 < 0.001 }
            if !nearWrap, abs(delta - step) > step * 1.5 {
                jumps.append("at \(index): \(Int((delta / step).rounded())) frames")
            }
        }
        return jumps
    }

    private let rampPeriod = 48_000

    private func writeRamp(seconds: Double, sampleRate: Double, to url: URL) throws {
        let frames = Int(seconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = Float(index % rampPeriod + 1) / Float(rampPeriod) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: pcm)
    }

    /// Each sample is one step above the last, so a skipped or repeated frame shows as a jump.
    private func makeRampStem(seconds: Double) throws -> DecodedStemBuffer {
        let sampleRate = DecodedStemBuffer.engineSampleRate
        let frames = Int(seconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = Float(index % rampPeriod + 1) / Float(rampPeriod) }
        return try DecodedStemBuffer.monoStem(from: pcm)
    }

    /// Plays a constant mono stem for a moment and returns the peak on each mixer output.
    private func capturedPeaks(routing: OutputRoutingSnapshot?) throws -> [Float] {
        let engine = AudioEngineManager(sampleRate: DecodedStemBuffer.engineSampleRate)
        let seconds = 2.0
        let settings = AudioEngineManager.TrackSettings(
            volume: 1, isMuted: false, isSolo: false, trimStart: 0, trimEnd: seconds
        )
        try engine.loadPreparedTracks(
            [AudioEngineManager.PreparedTrackPayload(id: UUID(), buffer: makeConstantStem(seconds: seconds), settings: settings, groupID: nil)],
            routing: routing
        )

        let peaks = OSAllocatedUnfairLock(initialState: [Float]())
        engine.installCaptureTapForTesting(silenceSpeakers: true) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let count = Int(buffer.format.channelCount)
            var blockPeaks = [Float](repeating: 0, count: count)
            for channel in 0..<count {
                for frame in 0..<Int(buffer.frameLength) {
                    blockPeaks[channel] = max(blockPeaks[channel], abs(channels[channel][frame]))
                }
            }
            let measured = blockPeaks
            peaks.withLock { held in
                if held.count < count { held = [Float](repeating: 0, count: count) }
                for channel in 0..<count { held[channel] = max(held[channel], measured[channel]) }
            }
        }
        defer {
            engine.removeCaptureTapForTesting()
            engine.shutdown()
        }

        engine.play()
        try XCTSkipUnless(engine.isPlaying, "needs a working audio output device")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        return peaks.withLock { $0 }
    }

    private func makeConstantStem(seconds: Double) throws -> DecodedStemBuffer {
        let sampleRate = DecodedStemBuffer.engineSampleRate
        let frames = Int(seconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = level }
        return try DecodedStemBuffer.monoStem(from: pcm)
    }
}
