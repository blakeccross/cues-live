import AVFoundation
import Foundation

/// One loaded track: the main thread's handle on what it plays, mixed by `StemMixer`.
final class TrackMemoryPlayer {
    /// Head of a loop kept resident by streaming sources. The reader polls every
    /// 40ms, so this only has to cover its catch-up latency after a wrap.
    static let loopPrefetchSeconds: TimeInterval = 2

    let trackID: UUID
    let sampleSource: any StemSampleSource
    private let renderContext: TrackRenderContext

    init(
        trackID: UUID,
        buffer: any StemSampleSource,
        transport: AudioPlaybackTransport,
        mapper: ArrangementTimelineMapper,
        outputSampleRate: Double = DecodedStemBuffer.engineSampleRate
    ) {
        self.trackID = trackID
        self.sampleSource = buffer
        self.renderContext = TrackRenderContext(
            transport: transport,
            buffer: buffer,
            mapper: mapper,
            outputSampleRate: outputSampleRate
        )
    }

    /// What `StemMixer` renders for this track.
    var mixerVoice: any MixerVoice { renderContext }

    /// Renders one block exactly as the mixer does; lets tests drive the render path
    /// with a deterministic clock.
    func renderBlock(
        frameCount: AVAudioFrameCount,
        hostTime: UInt64,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) {
        renderContext.render(frameCount: frameCount, hostTime: hostTime, outputBuffer: outputBuffer)
    }

    /// Stops reading sample data on the audio thread.
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
