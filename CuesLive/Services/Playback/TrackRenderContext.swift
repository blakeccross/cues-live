import AVFoundation
import Foundation

/// Renders one track on the audio thread.
///
/// The main thread changes what the track plays (arrangement, mix, key, playback window)
/// by publishing a new immutable `Settings` snapshot. The render thread reads the latest
/// snapshot without locking, so a fader drag or an edit never makes it wait. Replaced
/// snapshots, and any stretcher they alone held, are freed on the main thread.
final class TrackRenderContext: @unchecked Sendable {
    struct MixState: Sendable {
        var volume: Float = 1
        var pan: Float = 0
        var isAudible: Bool = true
    }

    struct Settings {
        var mapper: ArrangementTimelineMapper
        var mix = MixState()
        var playbackTimelineOffset: TimeInterval = 0
        var playbackEndTimeline: TimeInterval?
        var transposeSemitones: Float = 0
        /// Present while the track needs live stretching: a re-timed clip or a key change.
        /// Only the render thread calls into it; the main thread only creates and drops it.
        var stretcher: LiveStretcher?
        var isInvalidated = false
        /// Bumped to make the render thread land gain and pan on their targets without ramping.
        var rampSnapRequest: UInt64 = 0
    }

    private final class SettingsSnapshot {
        let settings: Settings

        init(_ settings: Settings) {
            self.settings = settings
        }
    }

    let transport: AudioPlaybackTransport
    let buffer: any StemSampleSource
    let sampleRate: Double
    let peakMeter = PeakMeterHolder()

    /// The main thread's copy of the latest published settings.
    private var settings: Settings
    private let published: RealtimeReference<SettingsSnapshot>

    // Render-thread state, carried from one block to the next.
    private var gainRamp = GainRamp()
    private var panRamp = PanRamp()
    private var appliedRampSnapRequest: UInt64 = 0
    private let gainRampFrames: Int

    init(
        transport: AudioPlaybackTransport,
        buffer: any StemSampleSource,
        mapper: ArrangementTimelineMapper
    ) {
        self.transport = transport
        self.buffer = buffer
        self.sampleRate = buffer.sampleRate
        self.gainRampFrames = max(1, Int(buffer.sampleRate * GainRamp.defaultRampSeconds))
        var settings = Settings(mapper: mapper)
        Self.refreshStretcher(in: &settings, buffer: buffer)
        self.settings = settings
        self.published = RealtimeReference(SettingsSnapshot(settings))
    }

    // MARK: - Main thread

    func invalidate() {
        change { $0.isInvalidated = true }
    }

    func updateMapper(_ mapper: ArrangementTimelineMapper) {
        change { settings in
            settings.mapper = mapper
            Self.refreshStretcher(in: &settings, buffer: buffer)
        }
    }

    func setTransposeSemitones(_ semitones: Float) {
        change { settings in
            settings.transposeSemitones = semitones
            Self.refreshStretcher(in: &settings, buffer: buffer)
        }
    }

    func updateMix(volume: Float, pan: Float, isAudible: Bool) {
        // Nothing is audible while stopped, so land on the new gain instead of
        // ramping into the start of the next play (a muted track would leak).
        let snapsRamps = !transport.isPlaying
        change { settings in
            settings.mix = MixState(volume: volume, pan: pan, isAudible: isAudible)
            if snapsRamps {
                settings.rampSnapRequest &+= 1
            }
        }
    }

    func setPlaybackWindow(offset: TimeInterval, endTimeline: TimeInterval?) {
        change { settings in
            settings.playbackTimelineOffset = offset
            settings.playbackEndTimeline = endTimeline
        }
    }

    /// Pins the source audio under the loop start. Call from the main thread.
    func prepareLoopPrefetch(atMasterTimeline masterLoopStart: TimeInterval?) {
        guard let masterLoopStart else {
            buffer.setPinnedRegion(sourceFrames: nil)
            return
        }

        let effectiveTimeline = masterLoopStart - settings.playbackTimelineOffset
        guard effectiveTimeline >= 0,
              let sourceSeconds = settings.mapper.sourceSeconds(atMasterTimeline: effectiveTimeline) else {
            buffer.setPinnedRegion(sourceFrames: nil)
            return
        }

        let startFrame = AudioPlaybackTransport.frameIndex(for: sourceSeconds, sampleRate: sampleRate)
        let length = max(1, Int(TrackMemoryPlayer.loopPrefetchSeconds * sampleRate))
        buffer.setPinnedRegion(sourceFrames: startFrame..<(startFrame + length))
    }

    /// Warms the sample source. Call from the main thread, or from other threads while the
    /// main thread waits for them, since it reads the main thread's copy of the settings.
    func prewarm(atTimelineSeconds timeline: TimeInterval) {
        let effectiveTimeline = timeline - settings.playbackTimelineOffset
        guard effectiveTimeline >= 0 else { return }
        let sourceSeconds = settings.mapper.sourceSeconds(atMasterTimeline: effectiveTimeline) ?? 0
        buffer.prewarm(aroundSourceFrame: Int(sourceSeconds * sampleRate))
    }

    private func change(_ edit: (inout Settings) -> Void) {
        edit(&settings)
        published.publish(SettingsSnapshot(settings))
    }

    /// Creates or drops the stretcher on the main thread, never the audio thread.
    /// Tracks at their original speed and key skip it and cost nothing extra.
    private static func refreshStretcher(in settings: inout Settings, buffer: any StemSampleSource) {
        let needsStretcher = settings.mapper.hasRetimedClips || abs(settings.transposeSemitones) > 0.001
        if needsStretcher, settings.stretcher == nil {
            settings.stretcher = LiveStretcher(channelCount: buffer.channelCount, sampleRate: buffer.sampleRate)
        } else if !needsStretcher {
            settings.stretcher = nil
        }
    }

    // MARK: - Render thread

    func render(
        frameCount: AVAudioFrameCount,
        hostTime: UInt64,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) {
        guard frameCount > 0, sampleRate > 0 else { return }
        Self.clearOutput(outputBuffer)
        published.withCurrent { snapshot in
            render(with: snapshot.settings, frameCount: frameCount, hostTime: hostTime, outputBuffer: outputBuffer)
        }
    }

    private func render(
        with settings: Settings,
        frameCount: AVAudioFrameCount,
        hostTime: UInt64,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) {
        guard !settings.isInvalidated else { return }

        let targetGain = Self.targetGain(for: settings.mix)
        if settings.rampSnapRequest != appliedRampSnapRequest {
            appliedRampSnapRequest = settings.rampSnapRequest
            gainRamp.snap(to: targetGain)
            panRamp.snap(to: settings.mix.pan)
        }
        // A muted track that has finished ramping out renders nothing.
        guard targetGain > 0 || gainRamp.current > 0 else { return }

        let rendered = renderPlayback(
            settings: settings,
            frameCount: frameCount,
            hostTime: hostTime,
            outputBuffer: outputBuffer
        )
        guard rendered else {
            // Silent block: keep the gain current so the next audible block
            // does not ramp from a stale value, and restart the stretcher on resume.
            settings.stretcher?.invalidatePosition()
            gainRamp.snap(to: targetGain)
            panRamp.snap(to: settings.mix.pan)
            return
        }

        // Stems render at unity and the ramp is applied once over the block, so a
        // fader, mute or solo change never steps the waveform.
        let buffers = UnsafeMutableAudioBufferListPointer(outputBuffer)
        gainRamp.apply(target: targetGain, to: buffers, frameCount: Int(frameCount), rampFrames: gainRampFrames)
        panRamp.apply(target: settings.mix.pan, to: buffers, frameCount: Int(frameCount), rampFrames: gainRampFrames)
        peakMeter.report(Self.peakAmplitude(in: outputBuffer, frameCount: frameCount))
    }

    private static func targetGain(for mix: MixState) -> Float {
        mix.isAudible ? max(mix.volume, 0) : 0
    }
}
