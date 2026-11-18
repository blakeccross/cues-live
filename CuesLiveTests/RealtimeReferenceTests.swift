import os
import XCTest
@testable import CuesLive

final class RealtimeReferenceTests: XCTestCase {
    /// Holds two copies of one number, so a reader that saw a freed or half-built probe
    /// would find them disagreeing. Counts live instances to prove replaced ones are freed.
    private final class Probe {
        static let liveCount = OSAllocatedUnfairLock(initialState: 0)
        let first: Int
        let second: Int

        init(_ value: Int) {
            first = value
            second = value
            Self.liveCount.withLock { $0 += 1 }
        }

        deinit {
            Self.liveCount.withLock { $0 -= 1 }
        }
    }

    func testPublishFreesTheReplacedObjectWhenTheRenderThreadIsNotUsingIt() {
        let reference = RealtimeReference(Probe(1))
        weak let replaced = reference.latest

        reference.publish(Probe(2))

        XCTAssertNil(replaced)
        XCTAssertEqual(reference.retiredCount, 0)
        XCTAssertEqual(reference.withCurrent { $0.first }, 2)
    }

    func testObjectInUseOnTheRenderThreadOutlivesItsReplacement() {
        let reference = RealtimeReference(Probe(1))
        weak let replaced = reference.latest

        let valueSeenAfterReplacement = reference.withCurrent { probe -> Int in
            reference.publish(Probe(2))
            return probe.first
        }

        XCTAssertEqual(valueSeenAfterReplacement, 1)
        XCTAssertNotNil(replaced, "kept until a later publish sees the render thread is done with it")
        reference.publish(Probe(3))
        XCTAssertNil(replaced)
        XCTAssertEqual(reference.retiredCount, 0)
    }

    func testConcurrentReaderNeverSeesAFreedObject() {
        let baseline = Probe.liveCount.withLock { $0 }
        do {
            let reference = RealtimeReference(Probe(0))
            let stopReading = OSAllocatedUnfairLock(initialState: false)
            let mismatches = OSAllocatedUnfairLock(initialState: 0)
            let readerFinished = DispatchGroup()

            readerFinished.enter()
            Thread.detachNewThread {
                while !stopReading.withLock({ $0 }) {
                    let consistent = reference.withCurrent { $0.first == $0.second }
                    if !consistent { mismatches.withLock { $0 += 1 } }
                }
                readerFinished.leave()
            }
            for value in 1...50_000 {
                reference.publish(Probe(value))
            }
            stopReading.withLock { $0 = true }
            readerFinished.wait()
            reference.publish(Probe(-1))

            XCTAssertEqual(mismatches.withLock { $0 }, 0)
            XCTAssertEqual(reference.retiredCount, 0)
            XCTAssertEqual(Probe.liveCount.withLock { $0 }, baseline + 1, "only the latest probe is alive")
        }
        XCTAssertEqual(Probe.liveCount.withLock { $0 }, baseline)
    }
}
