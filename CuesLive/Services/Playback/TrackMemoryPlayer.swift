import AVFoundation
import Foundation

/// Pull-based memory playback for one track via `AVAudioSourceNode`.
final class TrackMemoryPlayer {
    /// Head of a loop kept resident by streaming sources. The reader polls every
    /// 40ms, so this only has to cover its catch-up latency after a wrap.
    static let loopPrefetchSeconds: TimeInterval = 2

    let trackID: UUID
    let sourceNode: AVAudioSourceNode
    let sampleSource: any StemSampleSource
    private let renderContext: TrackRenderContext

    init(
        trackID: UUID,
        buffer: any StemSampleSource,
        transport: AudioPlaybackTransport,
        mapper: ArrangementTimelineMapper
    ) {
        self.trackID = trackID
        self.sampleSource = buffer
        self.renderContext = TrackRenderContext(
            transport: transport,
            buffer: buffer,
            mapper: mapper
        )

        let format = buffer.audioFormat
        // Unretained so the render thread never touches the context's reference count and
        // so can never be the one to free it. The engine stops before it releases a player.
        let context = Unmanaged.passUnretained(renderContext)

        sourceNode = AVAudioSourceNode(format: format) { _, timestamp, frameCount, outputData in
            let stamp = timestamp.pointee
            let hostTime = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : mach_absolute_time()

            context._withUnsafeGuaranteedRef { renderContext in
                renderContext.render(frameCount: frameCount, hostTime: hostTime, outputBuffer: outputData)
            }
            return noErr
        }
    }

    /// Renders one block exactly as the source node does; lets tests drive the render path
    /// with a deterministic clock.
    func renderBlock(
        frameCount: AVAudioFrameCount,
        hostTime: UInt64,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) {
        renderContext.render(frameCount: frameCount, hostTime: hostTime, outputBuffer: outputBuffer)
    }

    /// Stops reading sample data on the audio thread. Call before detaching the node.
    func invalidateRendering() {
        renderContext.invalidate()
    }

    func updateMapper(_ mapper: ArrangementTimelineMapper) {
        renderContext.updateMapper(mapper)
    }

    /// Shifts the track's pitch live. Zero plays it in its recorded key.
    func setTransposeSemitones(_ semitones: Float) {
        renderContext.setTransposeSemitones(semitones)
    }

    func updateMix(volume: Float, pan: Float, isAudible: Bool) {
        renderContext.updateMix(volume: volume, pan: pan, isAudible: isAudible)
    }

    func setPlaybackWindow(offset: TimeInterval, endTimeline: TimeInterval?) {
        renderContext.setPlaybackWindow(offset: offset, endTimeline: endTimeline)
    }

    func consumePeakMeter() -> Float {
        renderContext.peakMeter.consume()
    }

    func resetPeakMeter() {
        renderContext.peakMeter.reset()
    }

    /// Pins the source audio under the loop start so the frames rendered right
    /// after a wrap are already resident. Streaming stems evict pages behind the
    /// playhead, which otherwise silences the top of every loop pass.
    /// Pass `nil` when no loop is armed.
    func prepareLoopPrefetch(atMasterTimeline masterLoopStart: TimeInterval?) {
        renderContext.prepareLoopPrefetch(atMasterTimeline: masterLoopStart)
    }

    /// Warms the backing sample source for playback starting at the given master
    /// timeline position, so streaming sources have audio resident before play.
    func prewarm(atTimelineSeconds timeline: TimeInterval) {
        renderContext.prewarm(atTimelineSeconds: timeline)
    }
}
