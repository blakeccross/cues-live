import AVFoundation
import XCTest
@testable import CuesLive

/// Drives the real render path block by block to check where a scheduled section jump
/// lands in the output.
final class SectionTransitionRenderTests: XCTestCase {
    private let sampleRate = DecodedStemBuffer.engineSampleRate
    private let blockFrames: AVAudioFrameCount = 512
    private let clickSpacingFrames = 24_000

    private func hostTicks(seconds: TimeInterval) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return UInt64((seconds * 1_000_000_000 * Double(info.denom) / Double(info.numer)).rounded())
    }

    /// Clicks of 1.0 every half second, each followed by a short decaying tail.
    private func makeClickPCM(seconds: Double) throws -> AVAudioPCMBuffer {
        let frames = Int(seconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = 0 }
        var click = 0
        while click < frames {
            for tail in 0..<200 where click + tail < frames {
                data[click + tail] = 1.0 - Float(tail) / 200
            }
            click += clickSpacingFrames
        }
        return pcm
    }

    private func makeClickPlayer(transport: AudioPlaybackTransport, seconds: Double) throws -> TrackMemoryPlayer {
        let buffer = try DecodedStemBuffer.monoStem(from: makeClickPCM(seconds: seconds))
        return makePlayer(buffer: buffer, transport: transport, seconds: seconds)
    }

    private func makePlayer(
        buffer: any StemSampleSource,
        transport: AudioPlaybackTransport,
        seconds: Double,
        mapper customMapper: ArrangementTimelineMapper? = nil
    ) -> TrackMemoryPlayer {
        let mapper = customMapper ?? ArrangementTimelineMapper.linear(trimStart: 0, trimEnd: seconds)
        return TrackMemoryPlayer(trackID: UUID(), buffer: buffer, transport: transport, mapper: mapper)
    }

    private func renderBlock(_ player: TrackMemoryPlayer, hostTime: UInt64) throws -> [Float] {
        let channels = 1
        let byteSize = Int(blockFrames) * MemoryLayout<Float>.size
        let storage = UnsafeMutableRawPointer.allocate(byteCount: byteSize, alignment: 16)
        defer { storage.deallocate() }
        let listPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { listPointer.deallocate() }
        listPointer.pointee.mNumberBuffers = UInt32(channels)
        listPointer.pointee.mBuffers = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(byteSize),
            mData: storage
        )
        player.renderBlock(frameCount: blockFrames, hostTime: hostTime, outputBuffer: listPointer)
        let floats = storage.bindMemory(to: Float.self, capacity: Int(blockFrames))
        return Array(UnsafeBufferPointer(start: floats, count: Int(blockFrames)))
    }

    func testClipGainScalesTheRenderedBlock() throws {
        let transport = AudioPlaybackTransport()
        transport.setDuration(1)
        let seconds = 1.0
        let amplitude: Float = 0.25
        let frames = Int(seconds * sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        pcm.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(pcm.floatChannelData)[0]
        for index in 0..<frames { data[index] = amplitude }
        let buffer = try DecodedStemBuffer.monoStem(from: pcm)
        let trackID = UUID()
        func player(gainDB: Double) -> TrackMemoryPlayer {
            let clip = TrackClip(
                trackID: trackID,
                timelineStartSeconds: 0,
                duration: seconds,
                sourceStartSeconds: 0,
                gainDB: gainDB
            )
            let mapper = ArrangementTimelineMapper(clips: [clip], fileDuration: seconds)
            return makePlayer(buffer: buffer, transport: transport, seconds: seconds, mapper: mapper)
        }

        let hostTime = hostTicks(seconds: 100)
        transport.beginPlayback(from: 0)
        let unity = try renderBlock(player(gainDB: 0), hostTime: hostTime)
        XCTAssertEqual(unity[unity.count / 2], amplitude, accuracy: 0.000_1)

        transport.beginPlayback(from: 0)
        let boosted = try renderBlock(player(gainDB: 6.020599913279624), hostTime: hostTime)
        XCTAssertEqual(boosted[boosted.count / 2], amplitude * 2, accuracy: 0.001)

        transport.beginPlayback(from: 0)
        let silenced = try renderBlock(player(gainDB: -144), hostTime: hostTime)
        XCTAssertEqual(silenced[silenced.count / 2], 0, accuracy: 0.000_1)
    }

    func testReTimedClipPlaysItsClicksTwiceAsOften() throws {
        let transport = AudioPlaybackTransport()
        transport.setDuration(10)
        let player = try makeClickPlayer(transport: transport, seconds: 10)
        let clip = TrackClip(
            trackID: player.trackID,
            timelineStartSeconds: 0,
            duration: 5,
            sourceStartSeconds: 0,
            playbackRate: 2
        )
        player.updateMapper(ArrangementTimelineMapper(clips: [clip], fileDuration: 10))

        let origin = hostTicks(seconds: 100)
        transport.beginPlayback(from: 0)
        var output: [Float] = []
        for block in 0..<80 {
            let elapsed = Double(block) * Double(blockFrames) / sampleRate
            output += try renderBlock(player, hostTime: origin + hostTicks(seconds: elapsed))
        }

        // Source clicks every half second arrive every quarter second at 2x, on the timeline.
        for beat in 1...3 {
            let expected = beat * clickSpacingFrames / 2
            let window = (expected - 960)..<(expected + 960)
            let peak = window.max { abs(output[$0]) < abs(output[$1]) } ?? 0
            XCTAssertEqual(peak, expected, accuracy: 240, "click \(beat)")
        }
    }

    func testScheduledJumpPlaysTargetClickOnItsFirstFrame() throws {
        let transport = AudioPlaybackTransport()
        transport.setDuration(20)
        let player = try makeClickPlayer(transport: transport, seconds: 20)

        // 3.0 s is 281.25 blocks in: the jump lands a quarter of the way through a block.
        let transitionAt = 3.0
        let target = 8.0

        let origin = hostTicks(seconds: 100)
        transport.beginPlayback(from: 1)
        var output: [Float] = []
        let totalBlocks = 600
        for block in 0..<totalBlocks {
            if block == 10 {
                transport.scheduleTransition(to: target, at: transitionAt)
            }
            let elapsed = Double(block) * Double(blockFrames) / sampleRate
            output += try renderBlock(player, hostTime: origin + hostTicks(seconds: elapsed))
        }

        // Playback starts at 1.0 s. The block 0 anchor is the origin, so output frame n is
        // timeline 1.0 + n / sr, and the transition is hit at n = 2.0 * sr.
        let jumpFrame = Int(2.0 * sampleRate)
        XCTAssertEqual(output[jumpFrame - 1], 0, accuracy: 0.0001, "old section is silent just before its click-free end")
        XCTAssertEqual(output[jumpFrame], 1.0, accuracy: 0.0001, "first frame of the target must be the click's first frame")
        XCTAssertEqual(output[jumpFrame + 100], 0.5, accuracy: 0.0001)
    }

    func testJumpOnBlockBoundaryPlaysTargetClickOnItsFirstFrame() throws {
        let transport = AudioPlaybackTransport()
        transport.setDuration(20)
        let player = try makeClickPlayer(transport: transport, seconds: 20)

        // 512 blocks * 94 = 48128 frames after the start, a block boundary.
        let jumpFrame = Int(blockFrames) * 94
        let transitionAt = 1.0 + Double(jumpFrame) / sampleRate

        let origin = hostTicks(seconds: 100)
        transport.beginPlayback(from: 1)
        var output: [Float] = []
        for block in 0..<200 {
            if block == 10 {
                transport.scheduleTransition(to: 8, at: transitionAt)
            }
            let elapsed = Double(block) * Double(blockFrames) / sampleRate
            output += try renderBlock(player, hostTime: origin + hostTicks(seconds: elapsed))
        }

        XCTAssertEqual(output[jumpFrame], 1.0, accuracy: 0.0001)
    }

    /// Songs stream from disk, so a target outside the look-ahead window is not resident
    /// unless the engine pages it in (and keeps it) before the jump.
    func testStreamingTargetFarAheadIsAudibleWhenPinnedLikeTheEngine() throws {
        _ = try runStreamingJump(prepareTarget: true)
    }

    private func runStreamingJump(prepareTarget: Bool) throws -> Float {
        let seconds = 60.0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transition-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let pcm = try makeClickPCM(seconds: seconds)
        let file = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
        try file.write(from: pcm)

        let transport = AudioPlaybackTransport()
        transport.setDuration(seconds)
        let stream = try StreamingStemBuffer(url: url)
        stream.setReaderActive(true)
        defer { stream.setReaderActive(false) }
        let player = makePlayer(buffer: stream, transport: transport, seconds: seconds)

        let target = 40.0
        let transitionAt = 3.0
        let origin = hostTicks(seconds: 100)
        player.prewarm(atTimelineSeconds: 1)
        transport.beginPlayback(from: 1)

        var output: [Float] = []
        for block in 0..<300 {
            if block == 10 {
                if prepareTarget {
                    player.prepareLoopPrefetch(atMasterTimeline: target)
                }
                transport.scheduleTransition(to: target, at: transitionAt)
            }
            let elapsed = Double(block) * Double(blockFrames) / sampleRate
            output += try renderBlock(player, hostTime: origin + hostTicks(seconds: elapsed))
            Thread.sleep(forTimeInterval: 0.003)
        }
        let jumpFrame = Int(2.0 * sampleRate)
        let sample = output[jumpFrame]
        if prepareTarget {
            XCTAssertEqual(sample, 1.0, accuracy: 0.0001, "target click must be resident at the jump")
        }
        return sample
    }

    func testStreamingTargetFarAheadIsSilentWithoutPreparation() throws {
        let sample = try runStreamingJump(prepareTarget: false)
        // Documents why the engine pins the target before scheduling.
        XCTAssertEqual(sample, 0, accuracy: 0.0001)
    }

    /// Section starts come from arbitrary marker times, so the jump target (snapped to the
    /// nearest frame) often lands a hair before the section's exact start. That must still
    /// map into the section, not into a gap that silences the block.
    func testJumpToSectionWhoseStartIsNotFrameAlignedStillPlaysFirstClick() throws {
        for fractionOfAFrame in [0.2, 0.4, 0.6, 0.8] {
            let output = try renderJumpIntoArrangementSection(
                sectionStart: 3.0 + fractionOfAFrame / sampleRate
            )
            let jumpFrame = Int(2.0 * sampleRate)
            let window = output[jumpFrame...(jumpFrame + 2)]
            XCTAssertGreaterThan(
                window.max() ?? 0,
                0.9,
                "first click missing when section starts \(fractionOfAFrame) of a frame past a frame boundary"
            )
        }
    }

    private func renderJumpIntoArrangementSection(sectionStart: TimeInterval) throws -> [Float] {
        let seconds = 20.0
        let transport = AudioPlaybackTransport()
        transport.setDuration(seconds)
        let buffer = try DecodedStemBuffer.monoStem(from: makeClickPCM(seconds: seconds))

        let trackID = UUID()
        let mapper = ArrangementTimelineMapper(
            clips: [
                TrackClip(trackID: trackID, timelineStartSeconds: 0, duration: sectionStart, sourceStartSeconds: 0),
                TrackClip(trackID: trackID, timelineStartSeconds: sectionStart, duration: 6, sourceStartSeconds: 8),
            ],
            fileDuration: seconds
        )
        let player = makePlayer(buffer: buffer, transport: transport, seconds: seconds, mapper: mapper)

        // The engine snaps both the fire time and the target to the nearest frame.
        let snappedStart = AudioTimelineMath.quantize(sectionStart, sampleRate: sampleRate)
        let origin = hostTicks(seconds: 100)
        transport.beginPlayback(from: 1)
        var output: [Float] = []
        for block in 0..<400 {
            if block == 10 {
                transport.scheduleTransition(to: snappedStart, at: snappedStart)
            }
            let elapsed = Double(block) * Double(blockFrames) / sampleRate
            output += try renderBlock(player, hostTime: origin + hostTicks(seconds: elapsed))
        }
        return output
    }
}
