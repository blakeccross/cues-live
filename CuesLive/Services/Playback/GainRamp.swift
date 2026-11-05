import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Per-track gain smoother for the audio thread.
///
/// Fader, mute and solo changes arrive as a new target gain. Applying that target
/// to a whole block at once steps the waveform and clicks, so the first
/// `rampFrames` of the block ramp linearly from the previous gain and the rest
/// hold the target. The ramp always finishes inside the block it starts in, so
/// there is no state to carry across blocks beyond `current`.
///
/// Not thread-safe: the owner must serialise access (the render context's lock).
struct GainRamp {
    /// Long enough to avoid a click, short enough that a mute still feels immediate.
    static let defaultRampSeconds: Double = 0.005

    private(set) var current: Float

    init(initial: Float = 1) {
        current = initial
    }

    /// Jumps straight to `gain` without ramping. Use while nothing is audible.
    mutating func snap(to gain: Float) {
        current = gain
    }

    /// Scales every channel of `bufferList` in place, moving from `current` to
    /// `target`. A no-op when both are unity, which is the common case.
    mutating func apply(
        target: Float,
        to bufferList: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        rampFrames: Int
    ) {
        let start = current
        current = target
        guard frameCount > 0 else { return }

        if start == target {
            guard target != 1 else { return }
            for buffer in bufferList {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let count = Self.sampleCount(of: buffer, limit: frameCount)
                var gain = target
                vDSP_vsmul(data, 1, &gain, data, 1, vDSP_Length(count))
            }
            return
        }

        let rampCount = min(max(rampFrames, 1), frameCount)
        let step = (target - start) / Float(rampCount)
        for buffer in bufferList {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let count = Self.sampleCount(of: buffer, limit: frameCount)
            let rampedCount = min(rampCount, count)
            for index in 0..<rampedCount {
                data[index] *= start + step * Float(index)
            }
            if count > rampedCount {
                var gain = target
                let tail = data + rampedCount
                vDSP_vsmul(tail, 1, &gain, tail, 1, vDSP_Length(count - rampedCount))
            }
        }
    }

    private static func sampleCount(of buffer: AudioBuffer, limit: Int) -> Int {
        min(limit, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
    }
}

enum TrackPan {
    /// Balance law: centre is unity on both sides and moving off-centre attenuates only
    /// the far side, so a centred track is bit-identical to an unpanned one.
    static func channelGains(pan: Float) -> (left: Float, right: Float) {
        let clamped = min(1, max(-1, pan))
        return (min(1, 1 - clamped), min(1, 1 + clamped))
    }
}

/// Pans the first two channels of a render block, ramping so a pan move never steps the waveform.
struct PanRamp {
    private(set) var current: Float

    init(initial: Float = 0) {
        current = initial
    }

    mutating func snap(to pan: Float) {
        current = pan
    }

    /// A no-op while both the previous and target pan are centred.
    mutating func apply(
        target: Float,
        to bufferList: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        rampFrames: Int
    ) {
        let start = TrackPan.channelGains(pan: current)
        let end = TrackPan.channelGains(pan: target)
        current = target
        guard bufferList.count >= 2, frameCount > 0 else { return }

        Self.scale(bufferList[0], from: start.left, to: end.left, frameCount: frameCount, rampFrames: rampFrames)
        Self.scale(bufferList[1], from: start.right, to: end.right, frameCount: frameCount, rampFrames: rampFrames)
    }

    private static func scale(_ buffer: AudioBuffer, from start: Float, to target: Float, frameCount: Int, rampFrames: Int) {
        guard start != 1 || target != 1,
              let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let count = min(frameCount, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)

        var rampedCount = 0
        if start != target {
            rampedCount = min(max(rampFrames, 1), count)
            let step = (target - start) / Float(rampedCount)
            for index in 0..<rampedCount {
                data[index] *= start + step * Float(index)
            }
        }
        if count > rampedCount {
            var gain = target
            let tail = data + rampedCount
            vDSP_vsmul(tail, 1, &gain, tail, 1, vDSP_Length(count - rampedCount))
        }
    }
}
