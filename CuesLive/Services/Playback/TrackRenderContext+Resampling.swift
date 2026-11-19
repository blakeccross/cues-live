import AVFoundation

/// Reading a stem whose file rate differs from the mixer's.
extension TrackRenderContext {
    /// Mixes `frameCount` output frames from `sourceFrame` on, moving `sourceStep` source
    /// frames per output frame with 4-point Hermite interpolation. Each output frame maps
    /// straight to its source position, so consecutive blocks join without drift.
    func mixResampled(
        fromSourceFrame sourceFrame: Double,
        frameCount: Int,
        into outputBufferList: UnsafeMutablePointer<AudioBufferList>,
        outputFrameOffset: Int,
        gain: Float
    ) {
        guard let resampleWindow, frameCount > 0 else { return }
        let outputs = UnsafeMutableAudioBufferListPointer(outputBufferList)
        let channels = min(resampleChannelCount, outputs.count)
        guard channels > 0 else { return }

        var done = 0
        while done < frameCount {
            let frames = min(frameCount - done, StemMixer.maximumBusFrames)
            let start = sourceFrame + Double(done) * sourceStep
            // One frame before the first position and two after the last, for the interpolator.
            let first = Int(start.rounded(.down)) - 1
            let last = Int((start + Double(frames - 1) * sourceStep).rounded(.down)) + 2
            for channel in 0..<channels {
                guard let output = outputs[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let window = resampleWindow + channel * resampleCapacity
                fillWindow(window, channel: channel, from: first, through: last)
                for frame in 0..<frames {
                    let position = start + Double(frame) * sourceStep - Double(first)
                    let index = Int(position)
                    let fraction = Float(position - Double(index))
                    let sample = Self.hermite(
                        window[index - 1], window[index], window[index + 1], window[index + 2], fraction
                    )
                    output[outputFrameOffset + done + frame] = sample * gain
                }
            }
            done += frames
        }

        // A mono stem fills every channel of a wider bus, as `mixFromMemory` does.
        guard buffer.channelCount == 1, let mono = outputs[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        for channel in 1..<outputs.count {
            guard let extra = outputs[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
            (extra + outputFrameOffset).update(from: mono + outputFrameOffset, count: frameCount)
        }
    }

    /// Copies source frames `first...last` of `channel` into `window`, silent outside the stem.
    private func fillWindow(_ window: UnsafeMutablePointer<Float>, channel: Int, from first: Int, through last: Int) {
        window.update(repeating: 0, count: last - first + 1)
        let readStart = max(0, first)
        guard readStart <= last else { return }
        buffer.copy(
            channel: channel,
            startingFrame: readStart,
            frameCount: last - readStart + 1,
            into: window,
            destinationOffset: readStart - first,
            gain: 1
        )
    }

    private static func hermite(_ y0: Float, _ y1: Float, _ y2: Float, _ y3: Float, _ t: Float) -> Float {
        let slope = 0.5 * (y2 - y0)
        let curve = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
        let cubic = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
        return ((cubic * t + curve) * t + slope) * t + y1
    }
}
