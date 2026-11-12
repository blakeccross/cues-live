import AVFoundation
import Foundation
import os

/// Pull-based memory playback for one track via `AVAudioSourceNode`.
final class TrackMemoryPlayer {
    /// Head of a loop kept resident by streaming sources. The reader polls every
    /// 40ms, so this only has to cover its catch-up latency after a wrap.
    private static let loopPrefetchSeconds: TimeInterval = 2

    struct MixState: Sendable {
        var volume: Float = 1
        var pan: Float = 0
        var isAudible: Bool = true
    }

    private final class RenderContext: @unchecked Sendable {
        let transport: AudioPlaybackTransport
        let buffer: any StemSampleSource
        let sampleRate: Double
        var mapper: ArrangementTimelineMapper
        var mix = MixState()
        var playbackTimelineOffset: TimeInterval = 0
        var playbackEndTimeline: TimeInterval?
        let peakMeter = PeakMeterHolder()
        /// Present while the track needs live stretching: a re-timed clip or a key change.
        private var stretcher: LiveStretcher?
        private var transposeSemitones: Float = 0
        private var isInvalidated = false
        private var gainRamp = GainRamp()
        private var panRamp = PanRamp()
        private let gainRampFrames: Int
        private var stateLock = os_unfair_lock()

        init(
            transport: AudioPlaybackTransport,
            buffer: any StemSampleSource,
            mapper: ArrangementTimelineMapper
        ) {
            self.transport = transport
            self.buffer = buffer
            self.mapper = mapper
            self.sampleRate = buffer.sampleRate
            self.gainRampFrames = max(1, Int(buffer.sampleRate * GainRamp.defaultRampSeconds))
            refreshStretcher()
        }

        func invalidate() {
            os_unfair_lock_lock(&stateLock)
            isInvalidated = true
            os_unfair_lock_unlock(&stateLock)
        }

        func updateMapper(_ mapper: ArrangementTimelineMapper) {
            os_unfair_lock_lock(&stateLock)
            self.mapper = mapper
            os_unfair_lock_unlock(&stateLock)
            refreshStretcher()
        }

        func setTransposeSemitones(_ semitones: Float) {
            os_unfair_lock_lock(&stateLock)
            transposeSemitones = semitones
            os_unfair_lock_unlock(&stateLock)
            refreshStretcher()
        }

        /// Creates or drops the stretcher on the calling thread, never the audio thread.
        /// Tracks at their original speed and key skip it and cost nothing extra.
        private func refreshStretcher() {
            os_unfair_lock_lock(&stateLock)
            let needsStretcher = mapper.hasRetimedClips || abs(transposeSemitones) > 0.001
            let hasStretcher = stretcher != nil
            os_unfair_lock_unlock(&stateLock)

            if needsStretcher, !hasStretcher {
                let made = LiveStretcher(channelCount: buffer.channelCount, sampleRate: sampleRate)
                os_unfair_lock_lock(&stateLock)
                stretcher = made
                os_unfair_lock_unlock(&stateLock)
            } else if !needsStretcher, hasStretcher {
                os_unfair_lock_lock(&stateLock)
                let released = stretcher
                stretcher = nil
                os_unfair_lock_unlock(&stateLock)
                // Freed here, after the lock, so the audio thread never deallocates it.
                withExtendedLifetime(released) {}
            }
        }

        func updateMix(volume: Float, pan: Float, isAudible: Bool) {
            os_unfair_lock_lock(&stateLock)
            mix = MixState(volume: volume, pan: pan, isAudible: isAudible)
            // Nothing is audible while stopped, so land on the new gain instead of
            // ramping into the start of the next play (a muted track would leak).
            if !transport.isPlaying {
                gainRamp.snap(to: Self.targetGain(for: mix))
                panRamp.snap(to: mix.pan)
            }
            os_unfair_lock_unlock(&stateLock)
        }

        func setPlaybackWindow(offset: TimeInterval, endTimeline: TimeInterval?) {
            os_unfair_lock_lock(&stateLock)
            playbackTimelineOffset = offset
            playbackEndTimeline = endTimeline
            os_unfair_lock_unlock(&stateLock)
        }

        func render(
            frameCount: AVAudioFrameCount,
            hostTime: UInt64,
            outputBuffer: UnsafeMutablePointer<AudioBufferList>
        ) {
            guard frameCount > 0, sampleRate > 0 else { return }

            clearOutput(outputBuffer, frameCount: frameCount)

            // Hold the lock for the full render so mapper/mix cannot tear on the main thread.
            os_unfair_lock_lock(&stateLock)
            defer { os_unfair_lock_unlock(&stateLock) }
            guard !isInvalidated else { return }

            let targetGain = Self.targetGain(for: mix)
            // A muted track that has finished ramping out renders nothing.
            guard targetGain > 0 || gainRamp.current > 0 else { return }

            guard renderPlayback(frameCount: frameCount, hostTime: hostTime, outputBuffer: outputBuffer) else {
                // Silent block: keep the gain current so the next audible block
                // does not ramp from a stale value, and restart the stretcher on resume.
                stretcher?.invalidatePosition()
                gainRamp.snap(to: targetGain)
                panRamp.snap(to: mix.pan)
                return
            }

            // Stems render at unity and the ramp is applied once over the block, so a
            // fader, mute or solo change never steps the waveform.
            gainRamp.apply(
                target: targetGain,
                to: UnsafeMutableAudioBufferListPointer(outputBuffer),
                frameCount: Int(frameCount),
                rampFrames: gainRampFrames
            )
            panRamp.apply(
                target: mix.pan,
                to: UnsafeMutableAudioBufferListPointer(outputBuffer),
                frameCount: Int(frameCount),
                rampFrames: gainRampFrames
            )
            peakMeter.report(Self.peakAmplitude(in: outputBuffer, frameCount: frameCount))
        }

        /// Fills `outputBuffer` at unity gain. Returns `false` when nothing was
        /// rendered (transport stopped, or the track has not started / has ended).
        private func renderPlayback(
            frameCount: AVAudioFrameCount,
            hostTime: UInt64,
            outputBuffer: UnsafeMutablePointer<AudioBufferList>
        ) -> Bool {
            let transportState = transport.renderTimeline(atHostTime: hostTime, captureAnchor: true)
            guard transportState.isPlaying else { return false }

            let totalFrames = Int(frameCount)
            guard let split = transportState.transitionSplit else {
                return renderSegment(
                    masterStart: transportState.timelineSeconds,
                    outputStart: 0,
                    outputEnd: totalFrames,
                    outputBuffer: outputBuffer
                )
            }

            // A scheduled jump lands inside this block: render up to the jump from the
            // current position and the rest from the target, so the target's first frame
            // is the first frame after the jump rather than the start of the next block.
            let leadFrames = Int((split.secondsUntil * sampleRate - 1e-6).rounded(.up))
            let splitFrame = max(0, min(leadFrames, totalFrames))

            var didRender = false
            if splitFrame > 0 {
                didRender = renderSegment(
                    masterStart: transportState.timelineSeconds,
                    outputStart: 0,
                    outputEnd: splitFrame,
                    outputBuffer: outputBuffer
                )
            }
            if splitFrame < totalFrames {
                if renderSegment(
                    masterStart: split.targetOffset,
                    outputStart: splitFrame,
                    outputEnd: totalFrames,
                    outputBuffer: outputBuffer
                ) {
                    didRender = true
                }
            }
            return didRender
        }

        /// Renders output frames `outputStart..<outputEnd` with the master timeline at `masterStart`
        /// on the first of them.
        private func renderSegment(
            masterStart: TimeInterval,
            outputStart: Int,
            outputEnd: Int,
            outputBuffer: UnsafeMutablePointer<AudioBufferList>
        ) -> Bool {
            if let endTimeline = playbackEndTimeline, masterStart >= endTimeline {
                return false
            }

            let effectiveStart = masterStart - playbackTimelineOffset
            guard effectiveStart >= 0 else { return false }

            renderConstantTempo(
                masterStart: effectiveStart,
                outputStart: outputStart,
                outputEnd: outputEnd,
                outputBuffer: outputBuffer,
                transportMasterStart: masterStart
            )
            return true
        }

        private func regionRunFrames(
            regionSeconds: TimeInterval,
            remainingFrames: Int
        ) -> Int {
            min(
                AudioPlaybackTransport.frameSpan(forSeconds: regionSeconds, sampleRate: sampleRate),
                remainingFrames
            )
        }

        private func loopFrameBounds() -> (start: Int, end: Int)? {
            guard let loop = transport.currentLoopRegion(), loop.isValid, sampleRate > 0 else {
                return nil
            }
            let start = AudioPlaybackTransport.frameIndex(for: loop.start, sampleRate: sampleRate)
            let end = AudioPlaybackTransport.frameIndex(for: loop.end, sampleRate: sampleRate)
            guard end > start else { return nil }
            return (start, end)
        }

        /// Maps a continuously increasing master frame into the active loop via integer modulo.
        private func loopedMasterFrame(_ absoluteMasterFrame: Int, loop: (start: Int, end: Int)?) -> Int {
            guard let loop, absoluteMasterFrame >= loop.start else {
                return absoluteMasterFrame
            }
            let length = loop.end - loop.start
            return loop.start + ((absoluteMasterFrame - loop.start) % length)
        }

        private func renderConstantTempo(
            masterStart: TimeInterval,
            outputStart: Int,
            outputEnd: Int,
            outputBuffer: UnsafeMutablePointer<AudioBufferList>,
            transportMasterStart: TimeInterval
        ) {
            let loop = loopFrameBounds()
            let totalFrames = outputEnd

            var renderedFrames = outputStart
            // Unwrapped absolute frame from transport; looping is applied per-run via modulo.
            var absoluteMasterFrame = AudioPlaybackTransport.frameIndex(
                for: masterStart,
                sampleRate: sampleRate
            )
            let absoluteTransportOrigin = AudioPlaybackTransport.frameIndex(
                for: transportMasterStart,
                sampleRate: sampleRate
            )
            let transportOffsetFrames = absoluteTransportOrigin - absoluteMasterFrame
            let endFrame = playbackEndTimeline.map {
                AudioPlaybackTransport.frameIndex(for: $0, sampleRate: sampleRate)
            }

            while renderedFrames < totalFrames {
                let absoluteTransportFrame = absoluteMasterFrame + transportOffsetFrames
                if let endFrame, absoluteTransportFrame >= endFrame { break }

                let playbackMasterFrame = loopedMasterFrame(absoluteMasterFrame, loop: loop)
                let playbackMasterTime = Double(playbackMasterFrame) / sampleRate

                var maxRun = totalFrames - renderedFrames
                if let loop {
                    maxRun = min(maxRun, max(0, loop.end - playbackMasterFrame))
                }
                if let endFrame {
                    maxRun = min(maxRun, max(0, endFrame - absoluteTransportFrame))
                }
                guard maxRun > 0 else { break }

                let regionSeconds = mapper.regionRemainingSeconds(
                    fromMasterTimeline: playbackMasterTime,
                    bufferLimit: Double(maxRun) / sampleRate
                )
                let runFrames = regionRunFrames(
                    regionSeconds: regionSeconds,
                    remainingFrames: maxRun
                )

                guard runFrames > 0 else {
                    // Nothing mapped here: a gap past the last clip, or the tail of a
                    // trimmed region. Advance silently up to the wrap point rather than
                    // abandoning the buffer, so an armed loop still restarts on the exact
                    // frame instead of leaving the top of the loop silent.
                    guard loop != nil else { break }
                    renderedFrames += maxRun
                    absoluteMasterFrame += maxRun
                    continue
                }

                if let sourceStart = mapper.sourceSeconds(atMasterTimeline: playbackMasterTime) {
                    let gain = mapper.linearGain(atMasterTimeline: playbackMasterTime)
                    if let stretcher {
                        stretcher.render(
                            source: buffer,
                            timelineFrame: playbackMasterFrame,
                            sourceSeconds: sourceStart,
                            rate: mapper.playbackRate(atMasterTimeline: playbackMasterTime),
                            semitones: transposeSemitones,
                            frameCount: runFrames,
                            into: UnsafeMutableAudioBufferListPointer(outputBuffer),
                            outputOffset: renderedFrames,
                            gain: gain
                        )
                    } else {
                        mixFromMemory(
                            startingFrame: AudioPlaybackTransport.frameIndex(
                                for: sourceStart,
                                sampleRate: sampleRate
                            ),
                            frameCount: runFrames,
                            into: outputBuffer,
                            outputFrameOffset: renderedFrames,
                            gain: gain
                        )
                    }
                }

                renderedFrames += runFrames
                absoluteMasterFrame += runFrames
            }
        }

        private func mixFromMemory(
            startingFrame: Int,
            frameCount: Int,
            into outputBufferList: UnsafeMutablePointer<AudioBufferList>,
            outputFrameOffset: Int,
            gain: Float
        ) {
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputBufferList)
            let outputChannelCount = outputBuffers.count
            guard outputChannelCount > 0, frameCount > 0 else { return }

            // fill ch0; if the multi-channel connection hands us a wider ABL,
            // duplicate mono into additional channels so channel maps that
            // dual-route ch0 stay valid without reading missing inputs.
            if buffer.channelCount == 1 {
                guard let outputData = outputBuffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                _ = buffer.copy(
                    channel: 0,
                    startingFrame: startingFrame,
                    frameCount: frameCount,
                    into: outputData,
                    destinationOffset: outputFrameOffset,
                    gain: gain
                )
                for channel in 1..<outputChannelCount {
                    guard let extra = outputBuffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let dest = extra.advanced(by: outputFrameOffset)
                    let src = outputData.advanced(by: outputFrameOffset)
                    dest.update(from: src, count: frameCount)
                }
                return
            }

            if outputChannelCount >= 2, buffer.channelCount >= 2 {
                if let leftOutput = outputBuffers[0].mData?.assumingMemoryBound(to: Float.self) {
                    _ = buffer.copy(
                        channel: 0,
                        startingFrame: startingFrame,
                        frameCount: frameCount,
                        into: leftOutput,
                        destinationOffset: outputFrameOffset,
                        gain: gain
                    )
                }

                if let rightOutput = outputBuffers[1].mData?.assumingMemoryBound(to: Float.self) {
                    _ = buffer.copy(
                        channel: 1,
                        startingFrame: startingFrame,
                        frameCount: frameCount,
                        into: rightOutput,
                        destinationOffset: outputFrameOffset,
                        gain: gain
                    )
                }
                return
            }

            for channel in 0..<min(buffer.channelCount, outputChannelCount) {
                guard let outputData = outputBuffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                _ = buffer.copy(
                    channel: channel,
                    startingFrame: startingFrame,
                    frameCount: frameCount,
                    into: outputData,
                    destinationOffset: outputFrameOffset,
                    gain: gain
                )
            }
        }

        private func clearOutput(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: AVAudioFrameCount) {
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                memset(data, 0, Int(buffer.mDataByteSize))
            }
            _ = frameCount
        }

        private static func targetGain(for mix: MixState) -> Float {
            mix.isAudible ? max(mix.volume, 0) : 0
        }

        private static func peakAmplitude(
            in outputBuffer: UnsafeMutablePointer<AudioBufferList>,
            frameCount: AVAudioFrameCount
        ) -> Float {
            let buffers = UnsafeMutableAudioBufferListPointer(outputBuffer)
            guard frameCount > 0, !buffers.isEmpty else { return 0 }

            var peak: Float = 0
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let count = min(Int(frameCount), Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                for index in 0..<count {
                    peak = max(peak, abs(data[index]))
                }
            }
            return peak
        }

        func prepareLoopPrefetch(atMasterTimeline masterLoopStart: TimeInterval?) {
            guard let masterLoopStart else {
                buffer.setPinnedRegion(sourceFrames: nil)
                return
            }

            os_unfair_lock_lock(&stateLock)
            let offset = playbackTimelineOffset
            let mapper = mapper
            os_unfair_lock_unlock(&stateLock)

            let effectiveTimeline = masterLoopStart - offset
            guard effectiveTimeline >= 0,
                  let sourceSeconds = mapper.sourceSeconds(atMasterTimeline: effectiveTimeline) else {
                buffer.setPinnedRegion(sourceFrames: nil)
                return
            }

            let startFrame = AudioPlaybackTransport.frameIndex(
                for: sourceSeconds,
                sampleRate: sampleRate
            )
            let length = max(1, Int(TrackMemoryPlayer.loopPrefetchSeconds * sampleRate))
            buffer.setPinnedRegion(sourceFrames: startFrame..<(startFrame + length))
        }

        func prewarm(atTimelineSeconds timeline: TimeInterval) {
            os_unfair_lock_lock(&stateLock)
            let offset = playbackTimelineOffset
            let mapper = mapper
            os_unfair_lock_unlock(&stateLock)

            let effectiveTimeline = timeline - offset
            guard effectiveTimeline >= 0 else { return }
            let sourceSeconds = mapper.sourceSeconds(atMasterTimeline: effectiveTimeline) ?? 0
            let sourceFrame = Int(sourceSeconds * sampleRate)
            buffer.prewarm(aroundSourceFrame: sourceFrame)
        }
    }

    let trackID: UUID
    let sourceNode: AVAudioSourceNode
    let sampleSource: any StemSampleSource
    private let renderContext: RenderContext

    init(
        trackID: UUID,
        buffer: any StemSampleSource,
        transport: AudioPlaybackTransport,
        mapper: ArrangementTimelineMapper
    ) {
        self.trackID = trackID
        self.sampleSource = buffer
        self.renderContext = RenderContext(
            transport: transport,
            buffer: buffer,
            mapper: mapper
        )

        let format = buffer.audioFormat
        let context = renderContext

        sourceNode = AVAudioSourceNode(format: format) { [weak context] _, timestamp, frameCount, outputData in
            guard let context else {
                let buffers = UnsafeMutableAudioBufferListPointer(outputData)
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
                return noErr
            }
            let stamp = timestamp.pointee
            let hostTime = stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : mach_absolute_time()

            context.render(
                frameCount: frameCount,
                hostTime: hostTime,
                outputBuffer: outputData
            )
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
