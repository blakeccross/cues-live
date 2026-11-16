import AVFoundation
import Foundation
import os

/// Plays the click like a MIDI track drives a sampler: a list of click events on the timeline,
/// each triggering the accent or normal sample as playback reaches it. Nothing is rendered ahead.
///
/// The pattern can be swapped while playing, for a tempo edit or a new rhythm, without
/// rebuilding the audio graph. The render thread only ever try-locks, so it never waits.
final class ProceduralClickSource: StemSampleSource, @unchecked Sendable {
    /// The two samples a click sound plays: one on the downbeat, one on every other click.
    struct Hits: Sendable {
        let accent: [Float]
        let normal: [Float]

        static let none = Hits(accent: [], normal: [])
    }

    /// One click: where it starts and whether it is a downbeat.
    struct Event: Equatable, Sendable {
        let frame: Int
        let isAccent: Bool
    }

    /// Click events and the hits they trigger, fixed once built.
    final class Pattern: @unchecked Sendable {
        /// Identifies what the pattern was built from, so an unchanged edit skips the rebuild.
        struct Key: Equatable {
            let settings: ClickSettings
            let tempoChanges: [TempoChange]
            let timeSignatureChanges: [TimeSignatureChange]
            let duration: TimeInterval
        }

        let key: Key?
        /// In ascending frame order.
        let events: [Event]
        let hits: Hits

        init(key: Key?, events: [Event] = [], hits: Hits = .none) {
            self.key = key
            self.events = events
            self.hits = hits
        }

        static let silent = Pattern(key: nil)
    }

    /// Long enough for any song, so the timeline can grow without replacing the source.
    static let maximumDuration: TimeInterval = 6 * 60 * 60

    let sampleRate: Double
    let channelCount = 1
    let frameCount: Int
    let audioFormat: AVAudioFormat

    private var pattern: Pattern
    private var lock = os_unfair_lock()

    init(pattern: Pattern, sampleRate: Double = DecodedStemBuffer.engineSampleRate) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DecodedStemBufferError.unsupportedFormat
        }
        self.sampleRate = sampleRate
        frameCount = Int(Self.maximumDuration * sampleRate)
        audioFormat = format
        self.pattern = pattern
    }

    /// The pattern playing now. Call from the main thread.
    var currentPattern: Pattern {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return pattern
    }

    /// Takes effect on the next render block. Call from the main thread.
    func setPattern(_ newPattern: Pattern) {
        os_unfair_lock_lock(&lock)
        let previous = pattern
        pattern = newPattern
        os_unfair_lock_unlock(&lock)
        // Released here, outside the lock and off the audio thread.
        _ = previous
    }

    func copy(
        channel: Int,
        startingFrame: Int,
        frameCount requestedFrames: Int,
        into destination: UnsafeMutablePointer<Float>,
        destinationOffset: Int,
        gain: Float
    ) -> Int {
        guard channel == 0, startingFrame >= 0, startingFrame < frameCount else { return 0 }
        let available = min(requestedFrames, frameCount - startingFrame)
        guard available > 0 else { return 0 }

        let output = destination.advanced(by: destinationOffset)
        output.initialize(repeating: 0, count: available)
        // A pattern swap is in progress; one silent block is better than waiting.
        guard os_unfair_lock_trylock(&lock) else { return available }
        defer { os_unfair_lock_unlock(&lock) }

        mixClicks(from: pattern, startingFrame: startingFrame, count: available, gain: gain, into: output)
        return available
    }

    func interpolatedSample(channel: Int, frame: Double) -> Float {
        guard channel == 0, frame >= 0, frame < Double(frameCount) else { return 0 }
        var sample: Float = 0
        guard os_unfair_lock_trylock(&lock) else { return 0 }
        defer { os_unfair_lock_unlock(&lock) }
        mixClicks(from: pattern, startingFrame: Int(frame), count: 1, gain: 1, into: &sample)
        return sample
    }

    /// Adds every click sounding in `startingFrame ..< startingFrame + count` to `output`.
    private func mixClicks(
        from pattern: Pattern,
        startingFrame: Int,
        count: Int,
        gain: Float,
        into output: UnsafeMutablePointer<Float>
    ) {
        // Borrow every buffer once per block, so the loop does no reference counting.
        pattern.events.withUnsafeBufferPointer { events in
            pattern.hits.accent.withUnsafeBufferPointer { accent in
                pattern.hits.normal.withUnsafeBufferPointer { normal in
                    Self.mix(
                        events: events,
                        accent: accent,
                        normal: normal,
                        frames: startingFrame..<(startingFrame + count),
                        gain: gain,
                        into: output
                    )
                }
            }
        }
    }

    private static func mix(
        events: UnsafeBufferPointer<Event>,
        accent: UnsafeBufferPointer<Float>,
        normal: UnsafeBufferPointer<Float>,
        frames: Range<Int>,
        gain: Float,
        into output: UnsafeMutablePointer<Float>
    ) {
        // A click that started before this block may still be ringing into it.
        let earliestStart = frames.lowerBound - max(accent.count, normal.count)
        var index = firstEventIndex(in: events, atOrAfter: earliestStart)
        while index < events.count, events[index].frame < frames.upperBound {
            let event = events[index]
            let hit = event.isAccent ? accent : normal
            let first = max(frames.lowerBound, event.frame)
            let last = min(frames.upperBound, event.frame + hit.count)
            if first < last {
                for frame in first..<last {
                    output[frame - frames.lowerBound] += hit[frame - event.frame] * gain
                }
            }
            index += 1
        }
    }

    private static func firstEventIndex(in events: UnsafeBufferPointer<Event>, atOrAfter frame: Int) -> Int {
        var low = 0
        var high = events.count
        while low < high {
            let mid = (low + high) / 2
            if events[mid].frame < frame {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
