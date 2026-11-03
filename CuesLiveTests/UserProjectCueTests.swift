import AVFoundation
import SwiftData
import XCTest
@testable import CuesLive

/// Plays the performer's own "Praise" project through the real playback coordinator, cues
/// sections the way the live view does, and inspects the click track the engine renders.
/// Skips when the project is not on this machine.
@MainActor
final class UserProjectCueTests: XCTestCase {
    private struct Capture {
        var samples: [Float] = []
        var sampleRate: Double = 48_000
        var gapFrames = 0
    }

    private final class CaptureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var capture = Capture()
        private var firstSampleTime: Int64?

        func append(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
            guard let channel = buffer.floatChannelData?[0], time.isSampleTimeValid else { return }
            lock.lock(); defer { lock.unlock() }
            capture.sampleRate = buffer.format.sampleRate
            let start = time.sampleTime
            if firstSampleTime == nil { firstSampleTime = start }
            let expected = firstSampleTime! + Int64(capture.samples.count)
            if start > expected {
                let gap = Int(start - expected)
                capture.gapFrames += gap
                capture.samples.append(contentsOf: [Float](repeating: 0, count: gap))
            }
            capture.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        func snapshot() -> Capture {
            lock.lock(); defer { lock.unlock() }
            return capture
        }
    }

    private func loadSong() throws -> (Song, ModelContext) {
        let docs = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let url = docs.appendingPathComponent("cues.live/Songs/Praise-CAN YOU IMAGINE--A-127.00bpm.cueslive")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "Praise project not on this machine")
        let schema = Schema(PersistenceController.modelTypes)
        let context = ModelContext(try ModelContainer(
            for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
        let song = try SongProjectBridge.importProject(from: url, into: context)
        return (song, context)
    }

    // MARK: - Click analysis

    private struct Onset {
        let frame: Int
        let peak: Float
    }

    private func onsets(in samples: [Float], rate: Double, threshold: Float) -> [Onset] {
        var result: [Onset] = []
        let skip = Int(0.12 * rate)
        let window = Int(0.03 * rate)
        var index = 0
        while index < samples.count {
            if abs(samples[index]) > threshold {
                let end = min(samples.count, index + window)
                let peak = samples[index..<end].map { abs($0) }.max() ?? 0
                result.append(Onset(frame: index, peak: peak))
                index += skip
            } else {
                index += 1
            }
        }
        return result
    }

    private func readClickTrack(_ url: URL, seconds: Double) throws -> (samples: [Float], rate: Double) {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(min(Double(file.length), seconds * file.processingFormat.sampleRate))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        try file.read(into: buffer, frameCount: frames)
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        return (Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), file.processingFormat.sampleRate)
    }

    // MARK: - Scenario

    private struct CueStep {
        let afterSeconds: TimeInterval
        let sectionName: String
        /// Pick the first match at or after this timeline position (disambiguates repeated names).
        let occurrenceAfter: TimeInterval
    }

    func testCueRefrainWhilePlayingPraiseKeepsClickIntact() throws {
        let (song, context) = try loadSong()
        let clickTrack = try XCTUnwrap(song.sortedTracks.first { $0.displayName == "Click Track" })
        let clickURL = try XCTUnwrap(FileStore.trackURL(for: song, track: clickTrack))

        let setlist = Setlist(name: "Test \(UUID().uuidString)")
        setlist.showFilePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).cueshow").path
        context.insert(setlist)
        SetlistViewModel().insertSong(song, at: 0, to: setlist, context: context)

        let coordinator = PlaybackCoordinator()
        coordinator.configure(setlist: setlist)
        let loadDeadline = Date().addingTimeInterval(90)
        while !(coordinator.isLoaded && coordinator.currentWaveformSnapshot != nil), Date() < loadDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        try XCTSkipUnless(coordinator.isLoaded, "song did not load: \(coordinator.loadError ?? "unknown")")
        let sections = try XCTUnwrap(coordinator.currentWaveformSnapshot?.sections)

        let engine = coordinator.playbackEngine
        let box = CaptureBox()
        engine.installCaptureTapForTesting(trackID: clickTrack.id, silenceSpeakers: true) { buffer, time in
            box.append(buffer, time)
        }
        defer { engine.removeCaptureTapForTesting(); coordinator.stop() }

        coordinator.play()
        try XCTSkipUnless(coordinator.isPlaying, "needs a working audio output device")

        // Play, then cue Refrain from different places: a later Refrain, then back to the first.
        let steps: [CueStep] = [
            CueStep(afterSeconds: 1.0, sectionName: "Refrain", occurrenceAfter: 260),  // far forward
            CueStep(afterSeconds: 2.0, sectionName: "Refrain", occurrenceAfter: 0),    // back to the first
            CueStep(afterSeconds: 2.0, sectionName: "Refrain", occurrenceAfter: 18),   // the second
        ]

        struct CueRecord {
            let fireSourceSeconds: TimeInterval
            let targetSourceSeconds: TimeInterval
            let captureFramesWhenFired: Int
            let label: String
        }
        var records: [CueRecord] = []
        var current: CueRecord?
        var log: [String] = []
        var pending = steps
        var cued: (target: ArrangementDisplaySection, fireTime: TimeInterval)?
        var lastEvent: TimeInterval = 0
        let deadline = Date().addingTimeInterval(120)

        while Date() < deadline, coordinator.isPlaying {
            RunLoop.current.run(until: Date().addingTimeInterval(0.004))
            let now = coordinator.currentTime

            // The live view's cue monitor.
            if let active = cued, now >= active.fireTime || !coordinator.hasPendingSectionTransition {
                coordinator.snapToScheduledSection(active.target.timelineStartSeconds)
                log.append(String(format: "  cue fired; ui-time %.3fs -> playhead %.3fs", now, coordinator.currentTime))
                if let finished = current {
                    records.append(CueRecord(
                        fireSourceSeconds: finished.fireSourceSeconds,
                        targetSourceSeconds: finished.targetSourceSeconds,
                        captureFramesWhenFired: box.snapshot().samples.count,
                        label: finished.label
                    ))
                    current = nil
                }
                cued = nil
                lastEvent = coordinator.currentTime
                continue
            }

            if cued == nil, let step = pending.first, now >= lastEvent + step.afterSeconds {
                pending.removeFirst()
                guard let target = sections.first(where: {
                    $0.name == step.sectionName && $0.timelineStartSeconds >= step.occurrenceAfter
                }) else {
                    XCTFail("no section \(step.sectionName) after \(step.occurrenceAfter)s")
                    break
                }
                // Same rule as LivePlaybackView.sectionCueFireTime.
                let fireTime = sections.section(atTimeline: now)?.timelineEndSeconds
                    ?? sections.map(\.timelineEndSeconds).first(where: { $0 > now })
                    ?? target.timelineEndSeconds
                cued = (target, fireTime)
                let fromSection = sections.section(atTimeline: now)
                let fireSource = fromSection.map {
                    $0.sourceStartSeconds + (fireTime - $0.timelineStartSeconds)
                } ?? fireTime
                current = CueRecord(
                    fireSourceSeconds: fireSource,
                    targetSourceSeconds: target.sourceStartSeconds,
                    captureFramesWhenFired: 0,
                    label: String(format: "%@ (in %@ at %.2fs) -> %@ @%.3fs", step.sectionName,
                                  fromSection?.name ?? "?", now, target.name, target.timelineStartSeconds)
                )
                coordinator.scheduleSectionTransition(to: target.timelineStartSeconds, at: fireTime)
                log.append(String(
                    format: "cue at %.3fs (in %@) -> %@ at %.4fs, fires at %.4fs",
                    now, sections.section(atTimeline: now)?.name ?? "?", target.name,
                    target.timelineStartSeconds, fireTime
                ))
            }
            if pending.isEmpty, cued == nil, now > lastEvent + 6 { break }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        // MARK: Analysis against the real click file

        let capture = box.snapshot()
        let source = try readClickTrack(clickURL, seconds: 300)
        let rate = capture.sampleRate
        XCTAssertEqual(rate, source.rate, accuracy: 0.5)
        let sourceSamples = source.samples
        let captured = capture.samples

        /// Relative error of `captured[start..<start+length]` against `sourceSamples[sourceStart...]`
        /// after fitting a gain. Windows with no signal return nil.
        func mismatch(captureStart: Int, sourceStart: Int, length: Int) -> Float? {
            guard captureStart >= 0, sourceStart >= 0,
                  captureStart + length <= captured.count,
                  sourceStart + length <= sourceSamples.count else { return nil }
            var cc: Float = 0, cs: Float = 0, ss: Float = 0
            for i in 0..<length {
                let c = captured[captureStart + i], s = sourceSamples[sourceStart + i]
                cc += c * c; cs += c * s; ss += s * s
            }
            guard cc > 1e-6, ss > 1e-6 else { return nil }
            let gain = cs / ss
            let residual = cc - 2 * gain * cs + gain * gain * ss
            return (max(residual, 0) / cc).squareRoot()
        }

        /// Brute-force the source offset (source = capture + offset) around a guess.
        func refineOffset(guess: Int, captureStart: Int, length: Int, radius: Int) -> (offset: Int, error: Float)? {
            var best: (offset: Int, error: Float)?
            for offset in (guess - radius)...(guess + radius) {
                guard let error = mismatch(captureStart: captureStart, sourceStart: captureStart + offset, length: length) else { continue }
                if best == nil || error < best!.error { best = (offset, error) }
            }
            return best
        }

        /// Smallest mismatch over a few frames of slack (a click amplifies a one-frame slip).
        func bestMismatch(captureStart: Int, sourceStart: Int, length: Int, slack: Int = 6) -> Float? {
            (-slack...slack).compactMap {
                mismatch(captureStart: captureStart, sourceStart: sourceStart + $0, length: length)
            }.min()
        }

        /// First capture sample at or after `from` that is clearly part of a click.
        let capturePeak = captured.map { abs($0) }.max() ?? 1
        func firstOnset(from: Int) -> Int? {
            (from..<captured.count).first { abs(captured[$0]) > capturePeak * 0.2 }
        }

        var issues: [String] = []
        var lines: [String] = []

        // Playback starts at source 0: line the first clicks up, then refine to the sample.
        let sourcePeak = sourceSamples.map { abs($0) }.max() ?? 1
        let sourceFirst = try XCTUnwrap(sourceSamples.indices.first { abs(sourceSamples[$0]) > sourcePeak * 0.2 })
        let captureFirst = try XCTUnwrap(firstOnset(from: 0))
        let window = 4096
        guard let start = refineOffset(
            guess: sourceFirst - captureFirst, captureStart: max(0, captureFirst - 64), length: window, radius: 400
        ) else { return XCTFail("could not align capture with the click file\n\(log.joined(separator: "\n"))") }
        var offset = start.offset
        lines.append(String(format: "start aligned: capture is %d frames behind the file (error %.1f%%)", -offset, start.error * 100))

        for record in records {
            let fireFrame = Int((record.fireSourceSeconds * rate).rounded())
            let targetFrame = Int((record.targetSourceSeconds * rate).rounded())

            // Where the old audio ends in the capture, from the current alignment.
            let expectedEnd = fireFrame - offset

            // Cueing the section that is about to start anyway: nothing to jump, the audio must
            // simply carry on across the boundary without a restart.
            if abs(fireFrame - targetFrame) <= 2 {
                let across = bestMismatch(captureStart: expectedEnd - 6_000, sourceStart: expectedEnd - 6_000 + offset, length: 12_000)
                lines.append(String(
                    format: "%@: already-next section; audio across the boundary: %@",
                    record.label, across.map { String(format: "%.1f%% off", $0 * 100) } ?? "silent"
                ))
                if let across, across > 0.1 { issues.append("\(record.label): audio restarted or glitched at the boundary (\(Int(across * 100))%)") }
                continue
            }
            // The first block after that which stops matching marks the real jump (to ~1 ms).
            var jumpBlock = max(0, expectedEnd - 8192)
            while jumpBlock + 256 < captured.count {
                if let error = mismatch(captureStart: jumpBlock, sourceStart: jumpBlock + offset, length: 256), error > 0.2 { break }
                jumpBlock += 128
            }

            // Re-align the new section on a click well after the jump.
            guard let clickAfter = firstOnset(from: min(captured.count - 1, max(jumpBlock, expectedEnd) + 4096)) else {
                issues.append("\(record.label): no click captured after the jump")
                continue
            }
            let landing = clickAfter - 64
            let guess = targetFrame - max(jumpBlock, expectedEnd)
            guard let next = refineOffset(guess: guess, captureStart: landing, length: window, radius: 6000) else {
                issues.append("\(record.label): could not align audio after the jump")
                continue
            }
            let newOffset = next.offset
            let landedAt = targetFrame - newOffset // capture frame where the target's first sample plays
            let gap = landedAt - expectedEnd        // >0: audio missing, <0: audio repeated

            func rms(_ array: [Float], _ from: Int, _ count: Int) -> Float {
                guard from >= 0, from + count <= array.count else { return -1 }
                var total: Float = 0
                for i in from..<(from + count) { total += array[i] * array[i] }
                return (total / Float(count)).squareRoot()
            }
            let bin = Int(0.01 * rate)
            var bins: [String] = []
            for index in -4..<10 {
                let c = rms(captured, landedAt + index * bin, bin)
                let f = rms(sourceSamples, targetFrame + index * bin, bin)
                bins.append(String(format: "%+d0ms %.3f/%.3f", index, c, f))
            }
            lines.append("  [bins] capture/file rms: " + bins.joined(separator: ", "))
            let preError = bestMismatch(captureStart: expectedEnd - 12_000, sourceStart: expectedEnd - 12_000 + offset, length: 12_000)
            let firstClick = bestMismatch(captureStart: landedAt, sourceStart: targetFrame, length: Int(0.1 * rate))
            // The first 10 ms of the section hold the click's attack.
            let attackFrames = Int(0.01 * rate)
            let attackCaptured = rms(captured, landedAt, attackFrames)
            let attackFile = rms(sourceSamples, targetFrame, attackFrames)
            let sourceClick = (targetFrame..<min(sourceSamples.count, targetFrame + Int(0.2 * rate)))
                .first { abs(sourceSamples[$0]) > sourcePeak * 0.2 }
            lines.append(String(
                format: "%@: jump lands %+d frames from the fire point; last 270 ms before: %@; first 100 ms of the new section: %@; attack (first 10 ms) %.0f%% of the file's; file's click %@ after the section start",
                record.label, gap,
                preError.map { String(format: "%.1f%% off", $0 * 100) } ?? "silent",
                firstClick.map { String(format: "%.1f%% off", $0 * 100) } ?? "silent",
                attackFile > 0 ? Double(attackCaptured / attackFile) * 100 : 100,
                sourceClick.map { String(format: "%.1f ms", Double($0 - targetFrame) / rate * 1000) } ?? "none"
            ))
            if abs(gap) > 8 { issues.append("\(record.label): jump is \(gap) frames from where the section starts") }
            if let preError, preError > 0.1 { issues.append("\(record.label): audio before the jump differs from the file (\(Int(preError * 100))%)") }
            if let firstClick, firstClick > 0.1 { issues.append("\(record.label): first 100 ms of the new section differs from the file (\(Int(firstClick * 100))%)") }
            if attackFile > 0.01, attackCaptured < 0.8 * attackFile {
                issues.append(String(format: "%@: first click is missing or cut off (attack is %.0f%% of the file's)", record.label, Double(attackCaptured / attackFile) * 100))
            }
            offset = newOffset
        }

        let report = ([String(format: "captured %.1fs at %.0f Hz, capture gaps %d frames", Double(captured.count) / rate, rate, capture.gapFrames)]
            + log + lines + issues.map { "PROBLEM: \($0)" }).joined(separator: "\n")

        XCTAssertEqual(capture.gapFrames, 0, "capture dropped audio, results unreliable\n\(report)")
        XCTAssertEqual(records.count, steps.count, "not every cue fired\n\(report)")
        XCTAssertTrue(issues.isEmpty, "cue landed wrong\n\(report)")
    }
}
