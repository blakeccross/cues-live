import AVFoundation
import Foundation

/// Plays one track through Signalsmith Stretch on the audio thread, so a clip re-timed by a
/// tempo change follows the tempo and a key change shifts the pitch while the song plays.
///
/// The stretcher reads the source ahead of the playhead by its own latency, so its output
/// lines up with the timeline and the track needs no extra delay. When the timeline or the
/// source jumps (a seek, a loop wrap, a section jump, a clip edge) it restarts at the new
/// position. Create and release it off the audio thread; `render` allocates nothing.
final class LiveStretcher {
    /// Output frames per process call, so a rate change lands within about 10 ms.
    private static let chunkFrames = 512
    /// The fastest rate the read-ahead buffer is sized for. Faster clips play silence.
    static let maximumRate = 4.0
    /// How far a block may start from where the last one ended and still continue. The
    /// transport clock follows host time, which slips against the device's sample clock by
    /// a frame every second or so; restarting on each slip is audible, so the stretcher
    /// absorbs the difference in how much source it reads next.
    private static let continuitySeconds = 0.005

    let channelCount: Int
    private let handle: OpaquePointer
    private let inputLatency: Int
    private let outputLatency: Int
    private let inputCapacity: Int
    private let continuityFrames: Int
    private let inputChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    private let outputChannels: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>

    /// Next source frame to feed the stretcher.
    private var inputCursor = 0
    /// Where the next block must start to continue without a restart. Nil forces one.
    private var expectedTimelineFrame: Int?
    private var expectedSourceFrame = 0.0
    private var appliedSemitones: Float = 0

    init?(channelCount: Int, sampleRate: Double) {
        guard let handle = live_stretch_create(Int32(channelCount), sampleRate) else { return nil }
        self.handle = handle
        self.channelCount = channelCount
        inputLatency = Int(live_stretch_input_latency(handle))
        outputLatency = Int(live_stretch_output_latency(handle))
        inputCapacity = inputLatency
            + Int((Self.maximumRate * Double(outputLatency + Self.chunkFrames)).rounded(.up))
        continuityFrames = max(1, Int(sampleRate * Self.continuitySeconds))
        inputChannels = Self.allocateChannels(channelCount, frames: inputCapacity)
        outputChannels = Self.allocateChannels(channelCount, frames: Self.chunkFrames)
    }

    deinit {
        live_stretch_destroy(handle)
        for channel in 0..<channelCount {
            inputChannels[channel]?.deallocate()
            outputChannels[channel]?.deallocate()
        }
        inputChannels.deallocate()
        outputChannels.deallocate()
    }

    /// The next block restarts the stretcher instead of continuing the last one.
    func invalidatePosition() {
        expectedTimelineFrame = nil
    }

    /// Writes `frameCount` frames into `output` from `outputOffset`, for a stretch of track
    /// that starts at `timelineFrame` with the source at `sourceSeconds`, read at `rate`
    /// source seconds per timeline second and shifted by `semitones`.
    func render(
        source: any StemSampleSource,
        timelineFrame: Int,
        sourceSeconds: TimeInterval,
        rate: Double,
        semitones: Float,
        frameCount: Int,
        into output: UnsafeMutableAudioBufferListPointer,
        outputOffset: Int,
        gain: Float
    ) {
        guard rate > 0, rate <= Self.maximumRate, frameCount > 0 else {
            expectedTimelineFrame = nil
            return
        }
        if semitones != appliedSemitones {
            live_stretch_set_transpose_semitones(handle, semitones)
            appliedSemitones = semitones
        }

        let startFrame = sourceSeconds * source.sampleRate
        if !continues(atTimelineFrame: timelineFrame, sourceFrame: startFrame, rate: rate) {
            guard seek(source, toFrame: Int(startFrame.rounded()), rate: rate) else {
                expectedTimelineFrame = nil
                return
            }
        }

        var done = 0
        while done < frameCount {
            let frames = min(Self.chunkFrames, frameCount - done)
            let sourceEnd = startFrame + Double(done + frames) * rate
            let lead = Double(inputLatency) + rate * Double(outputLatency)
            let target = Int((sourceEnd + lead).rounded())
            let inputFrames = max(0, target - inputCursor)
            guard inputFrames <= inputCapacity else {
                // A big jump in rate: restart here rather than overrun the read-ahead buffer.
                guard seek(source, toFrame: Int((startFrame + Double(done) * rate).rounded()), rate: rate) else {
                    expectedTimelineFrame = nil
                    return
                }
                continue
            }

            readInput(from: source, startingAt: inputCursor, frameCount: inputFrames)
            inputChannels.withMemoryRebound(to: UnsafePointer<Float>?.self, capacity: channelCount) { input in
                live_stretch_process(handle, input, Int32(inputFrames), outputChannels, Int32(frames))
            }
            write(frames: frames, into: output, at: outputOffset + done, gain: gain)
            inputCursor += inputFrames
            done += frames
        }

        expectedTimelineFrame = timelineFrame + frameCount
        expectedSourceFrame = startFrame + Double(frameCount) * rate
    }

    /// True when a block starting here carries on from the last one, give or take clock slip.
    private func continues(atTimelineFrame timelineFrame: Int, sourceFrame: Double, rate: Double) -> Bool {
        guard let expectedTimelineFrame else { return false }
        return abs(timelineFrame - expectedTimelineFrame) <= continuityFrames
            && abs(sourceFrame - expectedSourceFrame) <= Double(continuityFrames) * max(rate, 1) + 1
    }

    /// Restarts so the next output frame plays `frame`. False when the rate needs more
    /// read-ahead than the buffer holds.
    private func seek(_ source: any StemSampleSource, toFrame frame: Int, rate: Double) -> Bool {
        let length = inputLatency + Int((rate * Double(outputLatency)).rounded(.up))
        guard length <= inputCapacity else { return false }
        readInput(from: source, startingAt: frame, frameCount: length)
        inputChannels.withMemoryRebound(to: UnsafePointer<Float>?.self, capacity: channelCount) { input in
            live_stretch_output_seek(handle, input, Int32(length))
        }
        inputCursor = frame + length
        return true
    }

    /// Copies source frames into the input buffer. Frames outside the file read as silence.
    private func readInput(from source: any StemSampleSource, startingAt start: Int, frameCount: Int) {
        guard frameCount > 0 else { return }
        let first = max(start, 0)
        let last = min(start + frameCount, source.frameCount)
        for channel in 0..<channelCount {
            guard let destination = inputChannels[channel] else { continue }
            destination.update(repeating: 0, count: frameCount)
            guard last > first else { continue }
            source.copy(
                channel: min(channel, source.channelCount - 1),
                startingFrame: first,
                frameCount: last - first,
                into: destination,
                destinationOffset: first - start,
                gain: 1
            )
        }
    }

    /// Mono stems feed every output channel; wider stems map channel for channel.
    private func write(
        frames: Int,
        into output: UnsafeMutableAudioBufferListPointer,
        at offset: Int,
        gain: Float
    ) {
        for outputChannel in 0..<output.count {
            let sourceChannel = channelCount == 1 ? 0 : outputChannel
            guard sourceChannel < channelCount,
                  let rendered = outputChannels[sourceChannel],
                  let destination = output[outputChannel].mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }
            for frame in 0..<frames {
                destination[offset + frame] = rendered[frame] * gain
            }
        }
    }

    private static func allocateChannels(
        _ count: Int,
        frames: Int
    ) -> UnsafeMutablePointer<UnsafeMutablePointer<Float>?> {
        let channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: count)
        for channel in 0..<count {
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            samples.initialize(repeating: 0, count: frames)
            channels[channel] = samples
        }
        return channels
    }
}
