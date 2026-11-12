import XCTest
@testable import CuesLive

final class AudioPlaybackTransportTests: XCTestCase {
    func testMappedTimelineAppliesPendingTransitionAtCorrectPoint() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(10)
        transport.scheduleTransition(to: 2, at: 3)

        // Before transition.
        XCTAssertEqual(transport.mappedTimeline(fromLinear: 2.5), 2.5, accuracy: 0.0000001)

        // Exactly at transition start: jumps to targetOffset.
        XCTAssertEqual(transport.mappedTimeline(fromLinear: 3.0), 2.0, accuracy: 0.0000001)

        // After transition: continues forward from the target offset.
        XCTAssertEqual(transport.mappedTimeline(fromLinear: 4.0), 3.0, accuracy: 0.0000001)
    }

    func testMappedTimelineClampsToDuration() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(10)
        transport.scheduleTransition(to: 2, at: 3)

        XCTAssertEqual(transport.mappedTimeline(fromLinear: 12.0), 10.0, accuracy: 0.0000001)
    }

    func testCancelScheduledTransitionClearsMapping() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(10)
        transport.scheduleTransition(to: 2, at: 3)
        transport.cancelScheduledTransition()

        // Without a pending transition, mapping should return the raw linear value.
        XCTAssertEqual(transport.mappedTimeline(fromLinear: 4.0), 4.0, accuracy: 0.0000001)
    }

    func testWrappedTimelineLoopsIntoHalfOpenRange() {
        let loop = AudioPlaybackTransport.LoopRegion(start: 0, end: 16)
        let sampleRate = DecodedStemBuffer.engineSampleRate

        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(0, loop: loop, sampleRate: sampleRate),
            0,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(15.999, loop: loop, sampleRate: sampleRate),
            15.999,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(16, loop: loop, sampleRate: sampleRate),
            0,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(16.25, loop: loop, sampleRate: sampleRate),
            0.25,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(32, loop: loop, sampleRate: sampleRate),
            0,
            accuracy: 0.0000001
        )
    }

    func testWrappedTimelineSupportsInteriorSectionLoops() {
        let loop = AudioPlaybackTransport.LoopRegion(start: 4, end: 8)
        let sampleRate = DecodedStemBuffer.engineSampleRate

        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(3.5, loop: loop, sampleRate: sampleRate),
            3.5,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(8, loop: loop, sampleRate: sampleRate),
            4,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(9.5, loop: loop, sampleRate: sampleRate),
            5.5,
            accuracy: 0.0000001
        )
    }

    func testFrameIndexKeepsSubSampleOffsetsOnSameFrame() {
        let sampleRate = 48_000.0

        XCTAssertEqual(AudioPlaybackTransport.frameIndex(for: 0, sampleRate: sampleRate), 0)
        XCTAssertEqual(
            AudioPlaybackTransport.frameIndex(for: 0.5 / sampleRate, sampleRate: sampleRate),
            0
        )
        XCTAssertEqual(
            AudioPlaybackTransport.frameIndex(for: 0.999 / sampleRate, sampleRate: sampleRate),
            0
        )
        XCTAssertEqual(
            AudioPlaybackTransport.frameIndex(for: 1.0 / sampleRate, sampleRate: sampleRate),
            1
        )
    }

    func testWrappedTimelineSnapsJustPastEndOntoFrameZero() {
        let loop = AudioPlaybackTransport.LoopRegion(start: 0, end: 16)
        let sampleRate = 48_000.0
        let justPastEnd = 16.0 + 0.25 / sampleRate

        XCTAssertEqual(
            AudioPlaybackTransport.wrappedTimeline(justPastEnd, loop: loop, sampleRate: sampleRate),
            0,
            accuracy: 0.0000001
        )
    }

    func testLoopedFrameZeroIsAudibleOnEveryIteration() {
        let sampleRate = 48_000.0
        let loopEnd = 16.0
        let endFrame = AudioPlaybackTransport.frameIndex(for: loopEnd, sampleRate: sampleRate)
        let loop = AudioPlaybackTransport.LoopRegion(start: 0, end: loopEnd)

        // Exact loop boundary and each subsequent iteration must map to frame 0
        // so the downbeat click is included like a DAW audio loop.
        for iteration in 0..<4 {
            let absolute = Double(endFrame * iteration) / sampleRate
            let wrapped = AudioPlaybackTransport.wrappedTimeline(
                absolute,
                loop: loop,
                sampleRate: sampleRate
            )
            XCTAssertEqual(
                AudioPlaybackTransport.frameIndex(for: wrapped, sampleRate: sampleRate),
                0,
                "iteration \(iteration) should land on frame 0"
            )
        }
    }

    func testFrameSpanKeepsTheFinalFrameOfARegion() {
        let sampleRate = 48_000.0

        // Region lengths are computed as `sectionEnd - master`, which is not exactly
        // representable. Flooring the raw product yields 0 here and silences the top
        // of a loop, because the render loop stops as soon as a run is empty.
        for sectionEnd in [8.0, 16.0, 33.0, 104.0, 200.0] {
            let lastFrame = AudioPlaybackTransport.frameIndex(for: sectionEnd, sampleRate: sampleRate) - 1
            let remaining = sectionEnd - (Double(lastFrame) / sampleRate)

            XCTAssertEqual(
                AudioPlaybackTransport.frameSpan(forSeconds: remaining, sampleRate: sampleRate),
                1,
                "section ending at \(sectionEnd)s must still render its final frame"
            )
        }
    }

    func testFrameSpanIsZeroOnlyForEmptyRegions() {
        let sampleRate = 48_000.0

        XCTAssertEqual(AudioPlaybackTransport.frameSpan(forSeconds: 0, sampleRate: sampleRate), 0)
        XCTAssertEqual(AudioPlaybackTransport.frameSpan(forSeconds: -1, sampleRate: sampleRate), 0)
        XCTAssertEqual(
            AudioPlaybackTransport.frameSpan(forSeconds: 0.4 / sampleRate, sampleRate: sampleRate),
            0
        )
        XCTAssertEqual(
            AudioPlaybackTransport.frameSpan(forSeconds: 1.9 / sampleRate, sampleRate: sampleRate),
            1
        )
        XCTAssertEqual(
            AudioPlaybackTransport.frameSpan(forSeconds: 0.5, sampleRate: sampleRate),
            24_000
        )
    }

    func testClearLoopRegionFoldsOntoAudiblePlayhead() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(32)
        transport.setLoopRegion(start: 4, end: 8)
        transport.beginPlayback(from: 13.5) // unwrapped: two passes + 1.5s into section

        let audible = AudioPlaybackTransport.wrappedTimeline(
            13.5,
            loop: AudioPlaybackTransport.LoopRegion(start: 4, end: 8),
            sampleRate: DecodedStemBuffer.engineSampleRate
        )
        XCTAssertEqual(audible, 5.5, accuracy: 0.0000001)

        transport.clearLoopRegion(continuingFrom: audible, hostTime: 1_000)

        XCTAssertFalse(transport.hasActiveLoopRegion)
        XCTAssertEqual(transport.pausedTimelineSeconds(), 5.5, accuracy: 0.0000001)

        // Anchored to the UI host time: reading with that same host time stays put.
        let state = transport.renderTimeline(atHostTime: 1_000, captureAnchor: false)
        XCTAssertEqual(state.timelineSeconds, 5.5, accuracy: 0.0000001)
    }

    private func hostTicks(seconds: TimeInterval) -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return UInt64(seconds * 1_000_000_000 * Double(info.denom) / Double(info.numer))
    }

    func testRenderTimelineReportsTransitionInsideBlock() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(60)
        transport.beginPlayback(from: 10)
        let origin: UInt64 = hostTicks(seconds: 100)
        _ = transport.renderTimeline(atHostTime: origin, captureAnchor: true)
        transport.scheduleTransition(to: 4, at: 10.5)

        let early = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 0.25), captureAnchor: false)
        XCTAssertEqual(early.timelineSeconds, 10.25, accuracy: 0.000001)
        XCTAssertEqual(early.transitionSplit?.secondsUntil ?? -1, 0.25, accuracy: 0.000001)
        XCTAssertEqual(early.transitionSplit?.targetOffset ?? -1, 4, accuracy: 0.000001)

        let after = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 0.5), captureAnchor: false)
        XCTAssertNil(after.transitionSplit)
        XCTAssertEqual(after.timelineSeconds, 4, accuracy: 0.000001)
    }

    func testAudioThreadReAnchorsOnTheJumpAndUIReadsDoNot() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(60)
        transport.beginPlayback(from: 10)
        let origin: UInt64 = hostTicks(seconds: 100)
        _ = transport.renderTimeline(atHostTime: origin, captureAnchor: true)
        transport.scheduleTransition(to: 4, at: 10.5)

        // A UI read past the jump sees the target but must not change the clock.
        let uiRead = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 0.52), captureAnchor: false)
        XCTAssertEqual(uiRead.timelineSeconds, 4.02, accuracy: 0.000001)
        XCTAssertTrue(transport.hasPendingTransition)

        // The first audio-thread read past the jump re-anchors at the exact jump moment.
        let audioRead = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 0.52), captureAnchor: true)
        XCTAssertEqual(audioRead.timelineSeconds, 4.02, accuracy: 0.000001)
        XCTAssertFalse(transport.hasPendingTransition)

        let later = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 0.62), captureAnchor: false)
        XCTAssertNil(later.transitionSplit)
        XCTAssertEqual(later.timelineSeconds, 4.12, accuracy: 0.000001)
    }

    func testBackToBackJumpsUseTheAudibleTimeline() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(60)
        transport.beginPlayback(from: 10)
        let origin: UInt64 = hostTicks(seconds: 100)
        _ = transport.renderTimeline(atHostTime: origin, captureAnchor: true)

        transport.scheduleTransition(to: 40, at: 10.5)
        _ = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 0.6), captureAnchor: true)

        // Audible time is now 40.1; a second jump is scheduled in that same timeline.
        transport.scheduleTransition(to: 5, at: 41)
        let beforeSecond = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 1.4), captureAnchor: true)
        XCTAssertEqual(beforeSecond.timelineSeconds, 40.9, accuracy: 0.000001)
        let afterSecond = transport.renderTimeline(atHostTime: origin + hostTicks(seconds: 1.6), captureAnchor: true)
        XCTAssertEqual(afterSecond.timelineSeconds, 5.1, accuracy: 0.000001)
    }

    func testRenderTimelineIgnoresStaleHostTimeBehindAnchor() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(32)
        transport.beginPlayback(from: 5.5)
        // Simulate an audio-thread anchor capture at a newer host time.
        _ = transport.renderTimeline(atHostTime: 2_000, captureAnchor: true)

        // UI still holding a stale lastRenderTime behind the anchor must not
        // underflow unsigned host-time math into a huge playhead.
        let stale = transport.renderTimeline(atHostTime: 1_000, captureAnchor: false)
        XCTAssertEqual(stale.timelineSeconds, 5.5, accuracy: 0.0000001)
    }

    func testAudibleTimelineWrapsUnderOneLock() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(32)
        transport.setLoopRegion(start: 4, end: 8)
        transport.beginPlayback(from: 13.5)
        _ = transport.renderTimeline(atHostTime: 1_000, captureAnchor: true)

        XCTAssertEqual(
            transport.audibleTimelineSeconds(atHostTime: 1_000),
            5.5,
            accuracy: 0.0000001
        )
    }

    func testClearLoopRegionWithoutContinuingFromLeavesPausedTimeline() {
        let transport = AudioPlaybackTransport()
        transport.setDuration(32)
        transport.setPausedTimeline(5.5)
        transport.setLoopRegion(start: 4, end: 8)
        transport.clearLoopRegion()

        XCTAssertFalse(transport.hasActiveLoopRegion)
        XCTAssertEqual(transport.pausedTimelineSeconds(), 5.5, accuracy: 0.0000001)
    }

}

