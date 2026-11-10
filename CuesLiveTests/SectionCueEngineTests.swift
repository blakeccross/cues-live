import AVFoundation
import XCTest
@testable import CuesLive

/// Plays a click track through the real engine, cues sections the way the live view does,
/// and inspects the audio the engine actually renders.
final class SectionCueEngineTests: XCTestCase {
    private let sampleRate = DecodedStemBuffer.engineSampleRate
    private let bpm = 117.0 // beats and bars land between frames, like real tempos
    private let songSeconds = 30.0
    private let sectionBars = 1
    private let clickFrames = 1_920

    private var accentTemplates: [[Float]] = []
    private var normalTemplates: [[Float]] = []

    // MARK: - Fixture

    private func clickBurst(amplitude: Float, frequency: Double) -> [Float] {
        (0..<clickFrames).map { frame in
            let t = Double(frame) / sampleRate
            return amplitude * Float(exp(-t / 0.006) * cos(2 * .pi * frequency * t))
        }
    }

    /// Each section clicks at its own pitch so the capture shows which section is playing.
    private func frequency(forSection index: Int) -> Double { 800 + 200 * Double(index) }

    private struct Fixture {
        let url: URL
        let trackID: UUID
        let layout: SongPlaybackLayout
        var sections: [SongSection] { layout.sections }
        let tempo: [TempoChange]
        let signatures: [TimeSignatureChange]
        let sectionSeconds: TimeInterval
    }

    private func makeFixture() throws -> Fixture {
        let tempo = [TempoChange(startMeasure: 1, bpm: bpm)]
        let signatures = [TimeSignatureChange(numerator: 4, denominator: 4, startMeasure: 1)]
        let barSeconds = 4 * 60.0 / bpm
        let sectionSeconds = barSeconds * Double(sectionBars)
        let markerCount = Int(songSeconds / sectionSeconds)

        accentTemplates = (0..<markerCount).map { clickBurst(amplitude: 1.0, frequency: frequency(forSection: $0)) }
        normalTemplates = (0..<markerCount).map { clickBurst(amplitude: 0.5, frequency: frequency(forSection: $0)) }

        let clicks = ClickTrackScheduler.scheduledClicks(
            from: 0, to: songSeconds,
            tempoChanges: tempo, timeSignatureChanges: signatures,
            subdivision: .quarter
        )
        let totalFrames = Int(songSeconds * sampleRate)
        var track = [Float](repeating: 0, count: totalFrames)
        for click in clicks {
            let section = min(markerCount - 1, Int(click.time / sectionSeconds))
            let template = click.isAccent ? accentTemplates[section] : normalTemplates[section]
            let startFrame = AudioPlaybackTransport.frameIndex(for: click.time, sampleRate: sampleRate)
            for offset in 0..<clickFrames where startFrame + offset < totalFrames {
                track[startFrame + offset] += template[offset]
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-click-\(UUID().uuidString).caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)))
        pcm.frameLength = AVAudioFrameCount(totalFrames)
        let channel = try XCTUnwrap(pcm.floatChannelData)[0]
        for (index, value) in track.enumerated() { channel[index] = value }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: pcm)

        let markers = (0..<markerCount).map {
            ArrangementMarker(name: "S\($0 + 1)", startSeconds: Double($0) * sectionSeconds, sortOrder: $0)
        }
        let trackID = UUID()
        let timeline = SongTimeline(
            markers: markers,
            clips: [.wholeFile(trackID: trackID, duration: songSeconds)]
        )
        return Fixture(
            url: url, trackID: trackID, layout: SongPlaybackLayout(timeline: timeline),
            tempo: tempo, signatures: signatures, sectionSeconds: sectionSeconds
        )
    }

    // MARK: - Capture

    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var samples: [Float] = []
        private var firstSampleTime: Int64?
        private(set) var gapFrames = 0

        func append(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
            guard let channel = buffer.floatChannelData?[0], time.isSampleTimeValid else { return }
            lock.lock(); defer { lock.unlock() }
            let start = time.sampleTime
            if firstSampleTime == nil { firstSampleTime = start }
            let expected = firstSampleTime! + Int64(samples.count)
            if start > expected {
                let gap = Int(start - expected)
                gapFrames += gap
                samples.append(contentsOf: [Float](repeating: 0, count: gap))
            }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        func snapshot() -> [Float] {
            lock.lock(); defer { lock.unlock() }
            return samples
        }
    }

    // MARK: - Analysis

    private struct Onset {
        let frame: Int
        let amplitude: Float
        var isAccent: Bool { amplitude > 0.75 }
    }

    private func onsets(in samples: [Float]) -> [Onset] {
        var result: [Onset] = []
        var index = 0
        while index < samples.count {
            if abs(samples[index]) > 0.05 {
                result.append(Onset(frame: index, amplitude: abs(samples[index])))
                index += clickFrames + 2_000 // skip the rest of this click
            } else {
                index += 1
            }
        }
        return result
    }

    /// Which section a click belongs to, from its pitch (zero crossings over the first 10 ms).
    private func section(of onset: Onset, in samples: [Float]) -> Int {
        let window = Int(0.010 * sampleRate)
        guard onset.frame + window < samples.count else { return -1 }
        var crossings = 0
        for offset in 1..<window where (samples[onset.frame + offset - 1] < 0) != (samples[onset.frame + offset] < 0) {
            crossings += 1
        }
        let frequency = Double(crossings) / 2 / 0.010
        return Int(((frequency - 800) / 200).rounded())
    }

    private struct Analysis {
        var issues: [String] = []
        var runs: [(section: Int, clicks: Int)] = []
    }

    private func analyze(_ samples: [Float]) -> Analysis {
        var analysis = Analysis()
        let found = onsets(in: samples)
        let beatFrames = 60.0 / bpm * sampleRate
        guard found.count > 8 else {
            analysis.issues.append("only \(found.count) clicks captured")
            return analysis
        }

        var pitchIndexes: [Int] = []
        for (index, onset) in found.enumerated() {
            let sectionIndex = section(of: onset, in: samples)
            pitchIndexes.append(sectionIndex)

            if index > 0 {
                let spacing = Double(onset.frame - found[index - 1].frame)
                if abs(spacing - beatFrames) > 1.5 {
                    analysis.issues.append(String(
                        format: "click %d at %.3fs: %.1f frames after the previous one (expected %.1f, %+.2f ms)",
                        index, Double(onset.frame) / sampleRate, spacing, beatFrames,
                        (spacing - beatFrames) / sampleRate * 1000
                    ))
                }
            }

            // A click cut off by a late jump starts partway through its decay.
            guard onset.frame + clickFrames + 2 <= samples.count else { continue }
            guard accentTemplates.indices.contains(sectionIndex) else {
                analysis.issues.append(String(
                    format: "click %d at %.3fs: unrecognizable pitch", index, Double(onset.frame) / sampleRate
                ))
                continue
            }
            let template = onset.isAccent ? accentTemplates[sectionIndex] : normalTemplates[sectionIndex]
            // The jump snaps to a whole frame and block starts follow the host clock, so a
            // click can sit a frame (21 µs) off the template; compare at the best of +-1.
            var bestRelativeError = Float.greatestFiniteMagnitude
            for shift in [0, -1, 1] {
                var squaredError: Float = 0
                var squaredTemplate: Float = 0
                for offset in 2..<(clickFrames - 2) {
                    let difference = samples[onset.frame + offset] - template[offset + shift]
                    squaredError += difference * difference
                    squaredTemplate += template[offset + shift] * template[offset + shift]
                }
                bestRelativeError = min(bestRelativeError, (squaredError / squaredTemplate).squareRoot())
            }
            let firstSampleIntact = abs(samples[onset.frame]) >= 0.8 * abs(template[0])
            if bestRelativeError > 0.1 || !firstSampleIntact {
                analysis.issues.append(String(
                    format: "click %d at %.3fs (section %d): not the source click (relative error %.0f%%, first sample %.3f vs %.3f)",
                    index, Double(onset.frame) / sampleRate, sectionIndex + 1,
                    bestRelativeError * 100, samples[onset.frame], template[0]
                ))
            }
        }

        // The accent has to stay on the downbeat.
        if let firstAccent = found.firstIndex(where: \.isAccent) {
            for (index, onset) in found.enumerated() where index >= firstAccent {
                if ((index - firstAccent) % 4 == 0) != onset.isAccent {
                    analysis.issues.append(String(
                        format: "click %d at %.3fs: accent pattern broken (amplitude %.2f)",
                        index, Double(onset.frame) / sampleRate, onset.amplitude
                    ))
                    break
                }
            }
        }

        for sectionIndex in pitchIndexes {
            if let last = analysis.runs.last, last.section == sectionIndex {
                analysis.runs[analysis.runs.count - 1].clicks += 1
            } else {
                analysis.runs.append((sectionIndex, 1))
            }
        }
        return analysis
    }

    // MARK: - Scenario

    private struct Cue {
        /// Seconds of playback after the previous cue has fired.
        let afterSeconds: TimeInterval
        let sectionIndex: Int
    }

    /// Returns the captured signal after running the cue script on the real engine.
    private func run(
        fixture: Fixture,
        bypassArrangement: Bool,
        cues: [Cue]
    ) throws -> (samples: [Float], log: [String], gapFrames: Int, cueRecords: [(inSection: Int, target: Int)]) {
        let engine = AudioEngineManager()
        let stream = try StreamingStemBuffer(url: fixture.url)
        let settings = AudioEngineManager.TrackSettings(
            volume: 1, isMuted: false, isSolo: false,
            trimStart: 0, trimEnd: songSeconds,
            bypassesArrangementMapping: bypassArrangement
        )
        if !bypassArrangement {
            engine.setArrangement(fixture.layout)
        }
        try engine.loadPreparedTracks([
            AudioEngineManager.PreparedTrackPayload(id: fixture.trackID, buffer: stream, settings: settings, groupID: nil)
        ])
        if !bypassArrangement {
            engine.setArrangement(fixture.layout)
        }
        engine.setTempoMap(fixture.tempo, referenceBPM: bpm, timeSignatureChanges: fixture.signatures)

        let capture = Capture()
        engine.installCaptureTapForTesting(silenceSpeakers: true) { buffer, time in capture.append(buffer, time) }
        defer { engine.removeCaptureTapForTesting(); engine.stop() }

        engine.play()
        try XCTSkipUnless(engine.isPlaying, "needs a working audio output device")

        var log: [String] = []
        var cueRecords: [(inSection: Int, target: Int)] = []
        var pendingCues = cues
        var cued: (target: TimeInterval, fireTime: TimeInterval)?
        var lastEventTime: TimeInterval = 0
        let deadline = Date().addingTimeInterval(songSeconds + 10)
        let sections = fixture.sections

        while Date() < deadline, engine.isPlaying {
            RunLoop.current.run(until: Date().addingTimeInterval(0.004))
            let now = engine.currentTime
            let livePlayhead = engine.livePlayheadTime()

            // The live view's cue monitor: fires once the playhead has reached the fire time.
            if let active = cued, now >= active.fireTime || !engine.hasPendingSectionTransition {
                engine.snapToTransitionTarget(active.target)
                log.append(String(
                    format: "  cue monitor fired at ui-time %.3fs (live playhead %.3fs); playhead now %.3fs",
                    now, livePlayhead, engine.currentTime
                ))
                cued = nil
                lastEventTime = engine.currentTime
            }

            if cued == nil, let next = pendingCues.first, now >= lastEventTime + next.afterSeconds {
                pendingCues.removeFirst()
                let target = sections[next.sectionIndex].timelineStartSeconds
                let fireTime = sections.first { $0.containsTimelineTime(now) }?.timelineEndSeconds
                    ?? sections.map(\.timelineEndSeconds).first { $0 > now } ?? target
                cued = (target, fireTime)
                let currentIndex = sections.firstIndex { $0.containsTimelineTime(now) } ?? 0
                cueRecords.append((currentIndex, next.sectionIndex))
                engine.scheduleTransition(to: target, at: fireTime)
                log.append(String(
                    format: "cue at %.3fs -> section %d (start %.4fs), fires at %.4fs",
                    now, next.sectionIndex + 1, target, fireTime
                ))
            }
            if pendingCues.isEmpty, cued == nil, now > lastEventTime + 3 { break }
        }
        // Let the last blocks arrive.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        return (capture.snapshot(), log, capture.gapFrames, cueRecords)
    }

    private let script: [Cue] = [
        Cue(afterSeconds: 1.0, sectionIndex: 5),   // forward, far
        Cue(afterSeconds: 1.5, sectionIndex: 1),   // backward, far
        Cue(afterSeconds: 1.5, sectionIndex: 3),   // forward, near
        Cue(afterSeconds: 2.0, sectionIndex: 8),   // forward, far
        Cue(afterSeconds: 1.0, sectionIndex: 2),   // backward, far
        Cue(afterSeconds: 2.0, sectionIndex: 6)    // forward
    ]

    private func assertCleanClickTrain(bypassArrangement: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        // Cue only after the previous cue has fired, using the timeline the audience hears.
        let result = try run(fixture: fixture, bypassArrangement: bypassArrangement, cues: script)
        let analysis = analyze(result.samples)
        var issues = analysis.issues

        // Expected order: play each section through, then jump to the cued one.
        let clicksPerSection = sectionBars * 4
        var expected: [Int] = []
        var next = 0
        for record in result.cueRecords {
            var index = next
            while index <= record.inSection {
                expected += [Int](repeating: index, count: clicksPerSection)
                index += 1
            }
            next = record.target
        }
        let captured = analysis.runs.flatMap { run in [Int](repeating: run.section, count: run.clicks) }
        let comparable = min(expected.count, captured.count)
        if let mismatch = (0..<comparable).first(where: { expected[$0] != captured[$0] }) {
            issues.append("click \(mismatch) played section \(captured[mismatch] + 1), expected section \(expected[mismatch] + 1)")
        }
        if captured.count < expected.count {
            issues.append("captured only \(captured.count) of \(expected.count) expected clicks")
        }

        let runs = analysis.runs.map { "S\($0.section + 1)x\($0.clicks)" }.joined(separator: " ")
        let shownIssues = Array(issues.prefix(30))
        let report = ([
            "bypassArrangement=\(bypassArrangement), captured \(String(format: "%.1f", Double(result.samples.count) / sampleRate))s, " +
            "\(onsets(in: result.samples).count) clicks, capture gaps \(result.gapFrames) frames",
            "sections heard: \(runs)",
            "sections expected: \(Dictionary(grouping: expected.indices, by: { $0 / clicksPerSection }).keys.sorted().map { "S\(expected[$0 * clicksPerSection] + 1)" }.joined(separator: " "))"
        ] + result.log + shownIssues.map { "PROBLEM: \($0)" } + (issues.count > 30 ? ["... \(issues.count - 30) more"] : [])).joined(separator: "\n")
        XCTAssertEqual(result.gapFrames, 0, "capture dropped audio, results unreliable\n\(report)", file: file, line: line)
        XCTAssertTrue(issues.isEmpty, "click train is not intact\n\(report)", file: file, line: line)
    }

    func testCuedSectionsKeepClickTrainIntactWithArrangementMapping() throws {
        try assertCleanClickTrain(bypassArrangement: false)
    }

    func testCuedSectionsKeepClickTrainIntactForGeneratedClick() throws {
        try assertCleanClickTrain(bypassArrangement: true)
    }
}
