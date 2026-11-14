import AVFoundation
import XCTest
@testable import CuesLive

final class ClipFadeRendererTests: XCTestCase {
    private let sampleRate = 48_000.0

    /// Runs the renderer over `frameCount` frames of ones in two channels, after `lead` untouched frames.
    private func render(_ clip: TrackClip, clipOffset: TimeInterval, lead: Int = 0, frameCount: Int) throws -> [[Float]] {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let total = lead + frameCount
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)))
        pcm.frameLength = AVAudioFrameCount(total)
        let channels = try XCTUnwrap(pcm.floatChannelData)
        for channel in 0..<2 {
            for frame in 0..<total { channels[channel][frame] = 1 }
        }
        ClipFadeRenderer.apply(
            clip,
            clipOffset: clipOffset,
            sampleRate: sampleRate,
            to: UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList),
            outputOffset: lead,
            frameCount: frameCount
        )
        return (0..<2).map { Array(UnsafeBufferPointer(start: channels[$0], count: total)) }
    }

    private func makeClip(fadeIn: ClipFade = .none, fadeOut: ClipFade = .none) -> TrackClip {
        TrackClip(
            trackID: UUID(),
            timelineStartSeconds: 0,
            duration: 1,
            sourceStartSeconds: 0,
            fadeIn: fadeIn,
            fadeOut: fadeOut
        )
    }

    func testFadeInFollowsItsCurveOnEveryChannel() throws {
        let clip = makeClip(fadeIn: ClipFade(duration: 0.01, shape: .sCurve, curvature: 0.4))
        let output = try render(clip, clipOffset: 0, frameCount: 600)
        XCTAssertEqual(output[0], output[1])
        XCTAssertEqual(output[0][0], 0)
        for frame in stride(from: 0, to: 600, by: 7) {
            let expected = clip.fadeGain(atOffset: Double(frame) / sampleRate)
            XCTAssertEqual(output[0][frame], expected, accuracy: 0.01, "frame \(frame)")
        }
        // The fade is 480 frames long; everything after it is untouched.
        XCTAssertEqual(Array(output[0][480...]), [Float](repeating: 1, count: 120))
    }

    func testFadeOutReachesSilenceAtTheClipEnd() throws {
        let clip = makeClip(fadeOut: ClipFade(duration: 0.01, shape: .linear))
        let start = 1 - 600 / sampleRate
        let output = try render(clip, clipOffset: start, frameCount: 600)
        // The fade starts at frame 120, inside the step that begins at 96.
        XCTAssertEqual(Array(output[0][..<96]), [Float](repeating: 1, count: 96))
        XCTAssertEqual(output[0][119], 1, accuracy: 0.02)
        XCTAssertEqual(output[0][360], 0.5, accuracy: 0.001)
        XCTAssertEqual(output[0][599], 1 / 480, accuracy: 0.001)
    }

    func testOnlyTheRequestedFramesAreShaped() throws {
        let clip = makeClip(fadeIn: ClipFade(duration: 0.5, shape: .linear))
        let output = try render(clip, clipOffset: 0, lead: 100, frameCount: 50)
        XCTAssertEqual(Array(output[0][..<100]), [Float](repeating: 1, count: 100))
        XCTAssertEqual(output[0][100], 0)
        XCTAssertLessThan(output[0][149], 0.01)
    }

    func testAudioBetweenTheFadesIsLeftAlone() throws {
        let clip = makeClip(fadeIn: ClipFade(duration: 0.1), fadeOut: ClipFade(duration: 0.1))
        let output = try render(clip, clipOffset: 0.4, frameCount: 512)
        XCTAssertEqual(output[0], [Float](repeating: 1, count: 512))
    }
}
