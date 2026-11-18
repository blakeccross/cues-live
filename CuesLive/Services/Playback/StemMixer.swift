import Accelerate
import AVFoundation
import Foundation

/// Mixes every voice (each loaded track and the Smart Guide voice) into the output on the
/// audio thread, routing each to its output channels.
///
/// Each voice renders into a stereo bus, with a mono stem on both sides, and the bus is
/// added onto the channels its `MixerRoute` names. The list of voices and their routes is
/// an immutable snapshot published from the main thread, so the render thread never waits.
final class StemMixer: @unchecked Sendable {
    struct Entry {
        let voice: any MixerVoice
        let route: MixerRoute
    }

    private final class Layout {
        let entries: [Entry]

        init(_ entries: [Entry]) {
            self.entries = entries
        }
    }

    /// Longest stretch a voice renders at once. Longer requests are split, with the host
    /// time advanced for each part.
    static let maximumBusFrames = 4096
    private static let busChannelCount = 2

    /// Stereo at the engine rate; connect it with a wider format to feed more outputs.
    let format: AVAudioFormat

    private let layout = RealtimeReference(Layout([]))

    private let bus: UnsafeMutableAudioBufferListPointer
    private let busSamples: UnsafeMutablePointer<Float>
    private let sampleRate: Double
    private let timebaseNumer: UInt32
    private let timebaseDenom: UInt32

    init(sampleRate: Double = DecodedStemBuffer.engineSampleRate) {
        var stereo = AudioChannelLayout()
        stereo.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: AVAudioChannelLayout(layout: &stereo))
        self.sampleRate = sampleRate
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        timebaseNumer = timebase.numer
        timebaseDenom = timebase.denom

        let sampleCount = Self.busChannelCount * Self.maximumBusFrames
        busSamples = .allocate(capacity: sampleCount)
        busSamples.initialize(repeating: 0, count: sampleCount)
        bus = AudioBufferList.allocate(maximumBuffers: Self.busChannelCount)
        for channel in 0..<Self.busChannelCount {
            bus[channel] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: 0,
                mData: busSamples + channel * Self.maximumBusFrames
            )
        }
    }

    deinit {
        free(bus.unsafeMutablePointer)
        busSamples.deallocate()
    }

    /// Replaces the voices the mixer renders. Main thread only.
    func setEntries(_ entries: [Entry]) {
        layout.publish(Layout(entries))
    }

    /// A source node that renders this mixer. The node does not retain the mixer, so the
    /// mixer must outlive it.
    func makeSourceNode() -> AVAudioSourceNode {
        let mixer = Unmanaged.passUnretained(self)
        return AVAudioSourceNode(format: format) { _, timestamp, frameCount, outputData in
            let stamp = timestamp.pointee
            let hostTime = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : mach_absolute_time()
            mixer._withUnsafeGuaranteedRef { $0.render(frameCount: frameCount, hostTime: hostTime, into: outputData) }
            return noErr
        }
    }

    /// Mixes one block into `output`, whose channels are the device's output channels.
    func render(frameCount: AVAudioFrameCount, hostTime: UInt64, into output: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }

        layout.withCurrent { layout in
            let totalFrames = Int(frameCount)
            var offset = 0
            while offset < totalFrames {
                let frames = min(Self.maximumBusFrames, totalFrames - offset)
                let partHostTime = hostTime &+ hostTicks(forFrames: offset)
                for index in layout.entries.indices {
                    mix(layout.entries[index], frames: frames, hostTime: partHostTime, at: offset, into: outputs)
                }
                offset += frames
            }
        }
    }

    private func mix(
        _ entry: Entry,
        frames: Int,
        hostTime: UInt64,
        at offset: Int,
        into outputs: UnsafeMutableAudioBufferListPointer
    ) {
        for channel in 0..<Self.busChannelCount {
            bus[channel].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
        }
        let rendered = entry.voice.render(
            frameCount: AVAudioFrameCount(frames),
            hostTime: hostTime,
            outputBuffer: bus.unsafeMutablePointer
        )
        guard rendered else { return }
        add(busChannel: 0, frames: frames, to: entry.route.left, at: offset, in: outputs)
        add(busChannel: 1, frames: frames, to: entry.route.right, at: offset, in: outputs)
    }

    private func add(
        busChannel: Int,
        frames: Int,
        to outputChannel: Int?,
        at offset: Int,
        in outputs: UnsafeMutableAudioBufferListPointer
    ) {
        guard let outputChannel, outputChannel < outputs.count,
              let destination = outputs[outputChannel].mData?.assumingMemoryBound(to: Float.self),
              Int(outputs[outputChannel].mDataByteSize) >= (offset + frames) * MemoryLayout<Float>.size else {
            return
        }
        let source = busSamples + busChannel * Self.maximumBusFrames
        let target = destination + offset
        vDSP_vadd(source, 1, target, 1, target, 1, vDSP_Length(frames))
    }

    private func hostTicks(forFrames frames: Int) -> UInt64 {
        guard frames > 0 else { return 0 }
        let nanoseconds = Double(frames) / sampleRate * 1_000_000_000
        return UInt64(nanoseconds * Double(timebaseDenom) / Double(timebaseNumer))
    }
}
