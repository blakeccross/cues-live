import AVFoundation
import Foundation

/// Plays short spoken callouts (Smart Guide) as a `StemMixer` voice, so they follow the
/// Guide group's output route and fader like any track.
///
/// Each callout is an immutable snapshot handed to the render thread without locking; a
/// new one restarts from its first sample.
final class AnnouncementSource: MixerVoice, @unchecked Sendable {
    private final class Callout {
        let samples: [Float]
        /// Tells the render thread a new callout arrived, even if it has the same address
        /// as one already freed.
        let serial: UInt64

        init(samples: [Float], serial: UInt64) {
            self.samples = samples
            self.serial = serial
        }
    }

    private let callout = RealtimeReference(Callout(samples: [], serial: 0))
    /// Main thread only.
    private var lastSerial: UInt64 = 0
    /// The gain as a float's bits, so the render thread reads it without locking.
    private let gainBits: UnsafeMutablePointer<UInt64>

    // Render-thread state.
    private var playingSerial: UInt64 = 0
    private var position = 0

    init() {
        gainBits = .allocate(capacity: 1)
        gainBits.initialize(to: UInt64(Float(1).bitPattern))
    }

    deinit {
        gainBits.deallocate()
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
        publish(samples)
    }

    func stop() {
        publish([])
    }

    /// Group fader / mute applied to the callout. Takes effect on the next render block.
    func setGain(_ gain: Float) {
        realtime_atomic_store_release(gainBits, UInt64(gain.bitPattern))
    }

    private func publish(_ samples: [Float]) {
        lastSerial += 1
        callout.publish(Callout(samples: samples, serial: lastSerial))
    }

    func render(
        frameCount: AVAudioFrameCount,
        hostTime: UInt64,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) -> Bool {
        let gain = Float(bitPattern: UInt32(truncatingIfNeeded: realtime_atomic_load_acquire(gainBits)))
        return callout.withCurrent { callout in
            if callout.serial != playingSerial {
                playingSerial = callout.serial
                position = 0
            }
            let frames = Int(frameCount)
            let copied = min(frames, max(0, callout.samples.count - position))
            callout.samples.withUnsafeBufferPointer { source in
                for buffer in UnsafeMutableAudioBufferListPointer(outputBuffer) {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for frame in 0..<copied {
                        data[frame] = source[position + frame] * gain
                    }
                    if copied < frames {
                        (data + copied).initialize(repeating: 0, count: frames - copied)
                    }
                }
            }
            position += copied
            return copied > 0
        }
    }
}
