import AVFoundation
import Foundation
import os

/// Plays short spoken callouts through an `AVAudioSourceNode`.
///
/// A source node (not a player node) is used so the output router can apply an AU channel map,
/// letting Smart Guide follow the Cues group's destination like any other track.
final class AnnouncementSource: @unchecked Sendable {
    let format: AVAudioFormat
    private(set) var sourceNode: AVAudioSourceNode!
    private let context = RenderContext()

    init?(sampleRate: Double = DecodedStemBuffer.engineSampleRate) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }
        self.format = format
        let context = context
        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, outputBuffer in
            context.render(frameCount: Int(frameCount), outputBuffer: outputBuffer)
            return noErr
        }
    }

    /// Restarts playback from the beginning of `stem`, cutting off any callout still speaking.
    func play(_ stem: DecodedStemBuffer) {
        guard stem.frameCount > 0 else { return }
        var samples = [Float](repeating: 0, count: stem.frameCount)
        samples.withUnsafeMutableBufferPointer { destination in
            guard let base = destination.baseAddress else { return }
            _ = stem.copy(
                channel: 0,
                startingFrame: 0,
                frameCount: stem.frameCount,
                into: base,
                destinationOffset: 0,
                gain: 1
            )
        }
        context.start(samples)
    }

    func stop() {
        context.start([])
    }

    /// Group fader / mute applied to the callout. Takes effect on the next render block.
    func setGain(_ gain: Float) {
        context.setGain(gain)
    }

    private final class RenderContext: @unchecked Sendable {
        private var lock = os_unfair_lock()
        private var samples: [Float] = []
        private var position = 0
        private var gain: Float = 1

        func start(_ samples: [Float]) {
            os_unfair_lock_lock(&lock)
            let previous = self.samples
            self.samples = samples
            position = 0
            os_unfair_lock_unlock(&lock)
            // Release the old buffer off the audio thread, outside the lock.
            _ = previous
        }

        func setGain(_ gain: Float) {
            os_unfair_lock_lock(&lock)
            self.gain = gain
            os_unfair_lock_unlock(&lock)
        }

        func render(frameCount: Int, outputBuffer: UnsafeMutablePointer<AudioBufferList>) {
            let buffers = UnsafeMutableAudioBufferListPointer(outputBuffer)

            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }

            let remaining = max(0, samples.count - position)
            let copied = min(frameCount, remaining)
            let currentGain = gain

            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                if copied > 0 {
                    samples.withUnsafeBufferPointer { source in
                        guard let base = source.baseAddress else { return }
                        for frame in 0..<copied {
                            data[frame] = base[position + frame] * currentGain
                        }
                    }
                }
                if copied < frameCount {
                    (data + copied).initialize(repeating: 0, count: frameCount - copied)
                }
            }
            position += copied
        }
    }
}
