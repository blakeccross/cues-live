import XCTest
@testable import CuesLive

final class WaveformPeakResamplerTimelineTests: XCTestCase {
    /// 32 samples per column at the default 100 columns per second.
    private let sampleRate = 3_200.0
    private let trackID = UUID()

    /// A mono file whose first second swings ±`first` and second second ±`second`.
    private func file(first: Float, second: Float) -> WaveformFileOverview {
        let samples = (0..<Int(sampleRate * 2)).map { index -> Float in
            let amplitude = index < Int(sampleRate) ? first : second
            return index.isMultiple(of: 2) ? amplitude : -amplitude
        }
        return WaveformFileOverview(sampleRate: sampleRate, channels: [WaveformOverview.build(samples)])
    }

    private func clip(at start: TimeInterval, duration: TimeInterval, source: TimeInterval) -> TrackClip {
        TrackClip(trackID: trackID, timelineStartSeconds: start, duration: duration, sourceStartSeconds: source)
    }

    func testTrimmedAudioIsNotDrawn() {
        let track = WaveformPeakResampler.TimelineTrack(
            overview: file(first: 0.5, second: 0.5),
            clips: [clip(at: 0, duration: 1, source: 0)]
        )

        let series = WaveformPeakResampler.timelineSummedMinMax(tracks: [track], timelineDuration: 2)

        XCTAssertEqual(series.count, 200)
        XCTAssertEqual(series.maxes[50], 1, accuracy: 0.001)
        XCTAssertEqual(series.maxes[150], 0, "the clip ends at one second")
        XCTAssertEqual(series.mins[150], 0)
    }

    func testAClipReadsItsOwnStretchOfTheFile() {
        // The clip skips the quiet first second and plays the loud one from the start.
        let track = WaveformPeakResampler.TimelineTrack(
            overview: file(first: 0.25, second: 1),
            clips: [clip(at: 0, duration: 1, source: 1)]
        )

        let series = WaveformPeakResampler.timelineSummedMinMax(tracks: [track], timelineDuration: 1)

        XCTAssertEqual(series.maxes[10], 1, accuracy: 0.001)
        XCTAssertEqual(series.mins[10], -1, accuracy: 0.001)
    }

    func testEachTrackUsesOnlyItsOwnClips() {
        let full = WaveformPeakResampler.TimelineTrack(
            overview: file(first: 0.5, second: 0.5),
            clips: [clip(at: 0, duration: 2, source: 0)]
        )
        let trimmed = WaveformPeakResampler.TimelineTrack(
            overview: file(first: 0.5, second: 0.5),
            clips: [clip(at: 0, duration: 1, source: 0)]
        )

        let series = WaveformPeakResampler.timelineSummedMinMax(tracks: [full, trimmed], timelineDuration: 2)

        XCTAssertEqual(series.maxes[50], 1, accuracy: 0.001, "both tracks play")
        XCTAssertEqual(series.maxes[150], 0.5, accuracy: 0.001, "only the untrimmed track plays")
    }

    func testATrackWithoutClipsIsSilent() {
        let track = WaveformPeakResampler.TimelineTrack(overview: file(first: 1, second: 1), clips: [])
        let series = WaveformPeakResampler.timelineSummedMinMax(tracks: [track], timelineDuration: 2)
        XCTAssertTrue(series.maxes.allSatisfy { $0 == 0 })
    }
}
