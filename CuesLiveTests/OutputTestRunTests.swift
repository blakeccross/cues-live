import AVFoundation
import XCTest
@testable import CuesLive

final class OutputTestRunTests: XCTestCase {
    private let outputs: [OutputDestination] = [.mono(channel: 1), .mono(channel: 2), .mono(channel: 3)]

    func testInstantSignalsAllJoinTheFirstCycle() throws {
        var run = try makeRun()
        var prepared: [OutputDestination] = []

        while let next = run.outputToPrepareBeforeCycle(isInstant: { _ in true }) {
            prepared.append(next)
            run.signals[next] = try makeSignal()
        }

        XCTAssertEqual(prepared, outputs)
    }

    func testSlowSignalsWaitOnlyForTheFirstOutput() throws {
        var run = try makeRun()

        XCTAssertEqual(run.outputToPrepareBeforeCycle(isInstant: { _ in false }), .mono(channel: 1))
        run.signals[.mono(channel: 1)] = try makeSignal()
        XCTAssertNil(run.outputToPrepareBeforeCycle(isInstant: { _ in false }))
    }

    func testCachedPhrasesJoinWhileUncachedOnesWait() throws {
        var run = try makeRun()
        run.signals[.mono(channel: 1)] = try makeSignal()

        let next = run.outputToPrepareBeforeCycle(isInstant: { $0 == .mono(channel: 3) })

        XCTAssertEqual(next, .mono(channel: 3))
    }

    func testFailedOutputsAreSkipped() throws {
        var run = try makeRun()
        run.failed = [.mono(channel: 1)]

        XCTAssertEqual(run.outputToPrepareBeforeCycle(isInstant: { _ in false }), .mono(channel: 2))
    }

    private func makeRun() throws -> OutputTestRun {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        return OutputTestRun(plan: OutputTestPlan(timing: .simultaneous), destinations: outputs, format: format)
    }

    private func makeSignal() throws -> AVAudioPCMBuffer {
        try XCTUnwrap(OutputTestSignalBuilder.pinkNoise(sampleRate: 48_000, duration: 0.01))
    }
}
