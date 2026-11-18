import os
import XCTest
@testable import CuesLive

final class RealtimeSnapshotTests: XCTestCase {
    /// Three counters that every update moves together, so a torn read shows up as a mismatch.
    private struct Counters: Equatable {
        var first: UInt64 = 0
        var second: UInt64 = 0
        var third: UInt64 = 0
    }

    func testUpdateReturnsTheTransformResultAndPublishesTheValue() {
        let snapshot = RealtimeSnapshot(Counters())

        let result = snapshot.update { counters -> UInt64 in
            counters.first = 7
            return counters.first * 2
        }

        XCTAssertEqual(result, 14)
        XCTAssertEqual(snapshot.load().first, 7)
    }

    func testConcurrentWritersLoseNoUpdatesAndReadersNeverSeeTornValues() {
        let snapshot = RealtimeSnapshot(Counters())
        let writers = 3
        let updatesPerWriter = 20_000
        let writersFinished = DispatchGroup()
        let readerFinished = DispatchGroup()
        let stopReading = OSAllocatedUnfairLock(initialState: false)
        let badReads = OSAllocatedUnfairLock(initialState: (torn: 0, backward: 0))

        readerFinished.enter()
        Thread.detachNewThread {
            var previous: UInt64 = 0
            while !stopReading.withLock({ $0 }) {
                let counters = snapshot.load()
                let isTorn = counters.first != counters.second || counters.second != counters.third
                let wentBackward = counters.first < previous
                if isTorn || wentBackward {
                    badReads.withLock { reads in
                        if isTorn { reads.torn += 1 }
                        if wentBackward { reads.backward += 1 }
                    }
                }
                previous = counters.first
            }
            readerFinished.leave()
        }

        for _ in 0..<writers {
            writersFinished.enter()
            Thread.detachNewThread {
                for _ in 0..<updatesPerWriter {
                    snapshot.update { counters in
                        counters.first += 1
                        counters.second += 1
                        counters.third += 1
                    }
                }
                writersFinished.leave()
            }
        }
        writersFinished.wait()
        stopReading.withLock { $0 = true }
        readerFinished.wait()

        let reads = badReads.withLock { $0 }
        XCTAssertEqual(reads.torn, 0)
        XCTAssertEqual(reads.backward, 0)
        XCTAssertEqual(snapshot.load().first, UInt64(writers * updatesPerWriter))
    }
}
