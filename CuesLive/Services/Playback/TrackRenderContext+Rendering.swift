import AVFoundation
import Foundation

/// Sample rendering for one block, from a settings snapshot.
extension TrackRenderContext {
    /// Fills `outputBuffer` at unity gain. Returns `false` when nothing was
    /// rendered (transport stopped, or the track has not started / has ended).
    func renderPlayback(
        settings: Settings,
        frameCount: AVAudioFrameCount,
        hostTime: UInt64,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) -> Bool {
        let transportState = transport.renderTimeline(atHostTime: hostTime, captureAnchor: true)
        guard transportState.isPlaying else { return false }

        let totalFrames = Int(frameCount)
        guard let split = transportState.transitionSplit else {
            return renderSegment(
                settings: settings,
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
                settings: settings,
                masterStart: transportState.timelineSeconds,
                outputStart: 0,
                outputEnd: splitFrame,
                outputBuffer: outputBuffer
            )
        }
        if splitFrame < totalFrames {
            if renderSegment(
                settings: settings,
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
        settings: Settings,
        masterStart: TimeInterval,
        outputStart: Int,
        outputEnd: Int,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) -> Bool {
        if let endTimeline = settings.playbackEndTimeline, masterStart >= endTimeline {
            return false
        }

        let effectiveStart = masterStart - settings.playbackTimelineOffset
        guard effectiveStart >= 0 else { return false }

        renderConstantTempo(
            settings: settings,
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
        settings: Settings,
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
        let endFrame = settings.playbackEndTimeline.map {
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

            let regionSeconds = settings.mapper.regionRemainingSeconds(
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

            if let sourceStart = settings.mapper.sourceSeconds(atMasterTimeline: playbackMasterTime) {
                let gain = settings.mapper.linearGain(atMasterTimeline: playbackMasterTime)
                if let stretcher = settings.stretcher {
                    stretcher.render(
                        source: buffer,
                        timelineFrame: playbackMasterFrame,
                        sourceSeconds: sourceStart,
                        rate: settings.mapper.playbackRate(atMasterTimeline: playbackMasterTime),
                        semitones: settings.transposeSemitones,
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
                if let clip = settings.mapper.fadedClip(atMasterTimeline: playbackMasterTime) {
                    ClipFadeRenderer.apply(
                        clip,
                        clipOffset: playbackMasterTime - clip.timelineStartSeconds,
                        sampleRate: sampleRate,
                        to: UnsafeMutableAudioBufferListPointer(outputBuffer),
                        outputOffset: renderedFrames,
                        frameCount: runFrames
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

    static func clearOutput(_ bufferList: UnsafeMutablePointer<AudioBufferList>) {
        for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }

    static func peakAmplitude(
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
}
