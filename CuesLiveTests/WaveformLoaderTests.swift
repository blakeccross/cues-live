import AVFoundation
import XCTest
@testable import CuesLive

final class WaveformLoaderTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDown() {
        tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        tempURLs = []
        super.tearDown()
    }

    /// Writes a mono file whose amplitude steps up each second: 0.1, 0.2, ... so peaks are predictable.
    private func makeSteppedFile(seconds: Int, sampleRate: Double = 44_100) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        tempURLs.append(url)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let framesPerSecond = Int(sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerSecond)))
        buffer.frameLength = AVAudioFrameCount(framesPerSecond)

        for second in 0..<seconds {
            let amplitude = Float(second + 1) / Float(seconds)
            let data = try XCTUnwrap(buffer.floatChannelData)[0]
            for frame in 0..<framesPerSecond {
                data[frame] = frame.isMultiple(of: 2) ? amplitude : -amplitude
            }
            try file.write(from: buffer)
        }
        return url
    }

    /// Left channel at full scale, right at half, so the two rows stay in proportion.
    private func makeStereoFile(seconds: Int, sampleRate: Double = 44_100) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        tempURLs.append(url)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let framesPerSecond = Int(sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesPerSecond)))
        buffer.frameLength = AVAudioFrameCount(framesPerSecond)
        let left = try XCTUnwrap(buffer.floatChannelData)[0]
        let right = try XCTUnwrap(buffer.floatChannelData)[1]

        for _ in 0..<seconds {
            for frame in 0..<framesPerSecond {
                let sample: Float = frame.isMultiple(of: 2) ? 1 : -1
                left[frame] = sample
                right[frame] = sample * 0.5
            }
            try file.write(from: buffer)
        }
        return url
    }

    func testPeakCountScalesWithDuration() {
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 10), 1024)
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 60), 6000)
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 120), 12_000)
        XCTAssertEqual(WaveformLoader.overviewSampleCount(forDuration: 3600), WaveformLoader.maximumSampleCount)
    }

    func testDecodedPeaksFollowAmplitude() throws {
        let url = try makeSteppedFile(seconds: 20)
        let peaks = WaveformLoader.loadPeaks(from: url)

        XCTAssertEqual(peaks.count, WaveformLoader.overviewSampleCount(forDuration: 20))
        XCTAssertEqual(peaks.max() ?? 0, 1, accuracy: 0.001)
        // Middle of second 5 (amplitude 6/20) normalized by the loudest second.
        let middle = peaks[Int(Double(peaks.count) * 5.5 / 20)]
        XCTAssertEqual(middle, 6.0 / 20.0, accuracy: 0.02)
    }

    func testRefineMatchesFullDecodeAndReportsProgress() throws {
        let url = try makeSteppedFile(seconds: 30)
        let preview = try XCTUnwrap(WaveformLoader.loadPreview(from: url))
        let sketch = preview.sketch()

        XCTAssertEqual(sketch.count, preview.sampleCount)
        XCTAssertGreaterThan(sketch.max() ?? 0, 0.9)

        let refined = WaveformLoader.refinePeaks(from: url, preview: preview) { partial in
            XCTAssertEqual(partial.count, preview.sampleCount)
        }
        XCTAssertEqual(refined, WaveformLoader.loadPeaks(from: url))
    }

    func testSampleColumnsBracketTheSamplesTheyCover() throws {
        let samples = (0..<2_000).map { index -> Float in
            sin(Float(index) * 0.05) + (index.isMultiple(of: 64) ? 0.8 : 0)
        }
        // The slice starts at file frame 400.
        let slice = Array(samples[400..<1_400])
        let columns = try XCTUnwrap(
            WaveformOverview.sampleColumns(
                samples: slice, origin: 400, fileEnd: 2_000, windowStart: 600, step: 40, overlap: 0, count: 10
            )
        )
        for (index, column) in columns.enumerated() {
            let from = 600 + index * 40
            let truth = samples[from..<(from + 40)]
            let got = try XCTUnwrap(column)
            XCTAssertLessThanOrEqual(got.0, truth.min() ?? 0)
            XCTAssertGreaterThanOrEqual(got.1, truth.max() ?? 0)
        }
    }

    func testSampleColumnsNeedTheSliceToCoverTheWindow() {
        let samples = [Float](repeating: 0.5, count: 100)
        XCTAssertNil(
            WaveformOverview.sampleColumns(
                samples: samples, origin: 1_000, fileEnd: 5_000, windowStart: 900, step: 10, overlap: 0, count: 5
            )
        )
        XCTAssertNil(
            WaveformOverview.sampleColumns(
                samples: samples, origin: 1_000, fileEnd: 5_000, windowStart: 1_080, step: 10, overlap: 0, count: 5
            )
        )
    }

    func testOverviewColumnsCoverEverySample() {
        let samples = (0..<2_000).map { index -> Float in
            sin(Float(index) * 0.05) + (index.isMultiple(of: 64) ? 0.8 : 0)
        }
        let overview = WaveformOverview.build(samples)
        let columns = overview.columns(start: 0, step: 40, count: 50)
        for (index, column) in columns.enumerated() {
            let from = index * 40
            let to = min(samples.count, from + 40)
            let slice = samples[from..<to]
            let got = try! XCTUnwrap(column)
            XCTAssertLessThanOrEqual(got.0, slice.min() ?? 0)
            XCTAssertGreaterThanOrEqual(got.1, slice.max() ?? 0)
        }
    }

    func testBuiltOverviewKeepsStereoLevels() throws {
        let url = try makeStereoFile(seconds: 1)
        let overview = try XCTUnwrap(WaveformOverviewBuilder.build(from: url))
        XCTAssertEqual(overview.channels.count, 2)
        XCTAssertTrue(overview.isComplete)
        let left = overview.channels[0].columns(start: 0, step: Double(overview.channels[0].sampleCount), count: 1)[0]
        let right = overview.channels[1].columns(start: 0, step: Double(overview.channels[1].sampleCount), count: 1)[0]
        XCTAssertEqual(try XCTUnwrap(left).0, -1, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(left).1, 1, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(right).0, -0.5, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(right).1, 0.5, accuracy: 0.02)
    }

    func testStereoPeaksKeepEachChannelOnOneScale() throws {
        let url = try makeStereoFile(seconds: 4)
        let channels = WaveformLoader.loadChannelPeaks(from: url)

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].count, channels[1].count)
        XCTAssertEqual(channels[0].max() ?? 0, 1, accuracy: 0.02)
        XCTAssertEqual(channels[1].max() ?? 0, 0.5, accuracy: 0.02)
        XCTAssertEqual(WaveformLoader.loadPeaks(from: url).max() ?? 0, 1, accuracy: 0.02)
    }

    func testSummedMinMaxAddsChannelsAndFiles() {
        let loud = [Float](repeating: 0.5, count: 3_200) + [Float](repeating: -1, count: 3_200)
        let quiet = [Float](repeating: 0.25, count: 6_400)
        let left = WaveformFileOverview(
            sampleRate: 3_200,
            channels: [WaveformOverview.build(loud)]
        )
        let right = WaveformFileOverview(
            sampleRate: 3_200,
            channels: [WaveformOverview.build(quiet)]
        )

        let summed = WaveformPeakResampler.summedMinMax(
            from: [(overview: left, duration: 2), (overview: right, duration: 2)],
            columnsPerSecond: 10
        )

        XCTAssertEqual(summed.count, 20)
        XCTAssertEqual(summed.mins[0], 1, accuracy: 0.02)
        XCTAssertEqual(summed.maxes[0], 1, accuracy: 0.02)
        XCTAssertEqual(summed.mins[19], -1, accuracy: 0.02)
        XCTAssertEqual(summed.maxes[19], -1, accuracy: 0.02)
    }

    func testSummedMinMaxAddsStereoChannels() {
        let overview = WaveformFileOverview(
            sampleRate: 100,
            channels: [
                WaveformOverview.build([Float](repeating: 0.4, count: 128)),
                WaveformOverview.build([Float](repeating: -0.2, count: 128))
            ]
        )
        let summed = WaveformPeakResampler.summedMinMax(
            from: [(overview: overview, duration: 1.28)],
            columnsPerSecond: 10
        )

        XCTAssertGreaterThan(summed.count, 0)
        XCTAssertEqual(summed.mins[0], 1, accuracy: 0.02)
        XCTAssertEqual(summed.maxes[0], 1, accuracy: 0.02)
    }

    func testTimelineMinMaxLeavesGapsSilent() {
        let source = WaveformMinMax(mins: [0.2, -0.4], maxes: [0.8, 0.1])
        let clip = TrackClip(
            trackID: UUID(),
            timelineStartSeconds: 1,
            duration: 1,
            sourceStartSeconds: 0
        )
        let laid = WaveformPeakResampler.timelineMinMax(
            from: source,
            fileDuration: 2,
            clips: [clip],
            timelineDuration: 2
        )

        XCTAssertEqual(laid.mins[0], 0)
        XCTAssertEqual(laid.maxes[0], 0)
        XCTAssertEqual(laid.mins[1], 0.2, accuracy: 0.001)
        XCTAssertEqual(laid.maxes[1], 0.8, accuracy: 0.001)
    }

    func testDisplayColumnsUseTheWindowExtrema() throws {
        let mins: [Float] = [-0.2, -0.8, -0.1]
        let maxes: [Float] = [0.2, 0.4, 0.9]
        let prepared = try XCTUnwrap(
            WaveformColumnGeometry.prepare(
                mins: mins,
                maxes: maxes,
                contentWidth: 3,
                rect: CGRect(x: 0, y: 0, width: 3, height: 10),
                scale: 1,
                half: 100
            )
        )

        XCTAssertEqual(prepared.columns.count, 3)
        XCTAssertEqual(prepared.columns[1].min, -0.8, accuracy: 0.001)
        XCTAssertEqual(prepared.columns[1].max, 0.4, accuracy: 0.001)
    }

    func testGroupedMaximaKeepsEachGroupsPeak() {
        let peaks: [Float] = [0.1, 0.5, 0.2, 0.9, 0.3, 0.4, 0.8]
        XCTAssertEqual(
            WaveformPeakResampler.groupedMaxima(of: peaks, groupSize: 3, groups: 0...2),
            [0.5, 0.9, 0.8]
        )
    }

    func testGroupedMaximaOmitsGroupsPastTheEnd() {
        let peaks: [Float] = [0.1, 0.5, 0.2, 0.9]
        XCTAssertEqual(
            WaveformPeakResampler.groupedMaxima(of: peaks, groupSize: 2, groups: 1...5),
            [0.9]
        )
    }

    func testGroupedMaximaOfSizeOneIsIdentity() {
        let peaks: [Float] = [0.1, 0.5, 0.2]
        XCTAssertEqual(
            WaveformPeakResampler.groupedMaxima(of: peaks, groupSize: 1, groups: 0...2),
            peaks
        )
    }
}
