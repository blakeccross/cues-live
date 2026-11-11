import Accelerate
import AVFoundation
import CryptoKit
import Foundation

enum WaveformLoader {
    /// Peak overview density, decoded once per audio file. Detail is fixed per second of audio,
    /// so long songs are as sharp as short ones (until `maximumSampleCount` is reached).
    static let peaksPerSecond = 100
    static let minimumSampleCount = 1024
    /// Bounds decode time and memory for very long stems (~11 minutes at full density).
    static let maximumSampleCount = 65_536
    /// Bumped whenever the overview layout changes so stale caches are ignored.
    static let overviewVersion = 2

    static func overviewSampleCount(forDuration duration: TimeInterval) -> Int {
        let wanted = Int((duration * Double(peaksPerSecond)).rounded(.up))
        return min(maximumSampleCount, max(minimumSampleCount, wanted))
    }

    static func loadPeaks(from url: URL, targetSampleCount: Int? = nil) -> [Float] {
        normalize(loadRawPeaks(from: url, targetSampleCount: targetSampleCount))
    }

    /// One normalized peak row per channel, at most two. Levels share one scale, so a quieter
    /// channel stays shorter.
    static func loadChannelPeaks(from url: URL, targetSampleCount: Int? = nil) -> [[Float]] {
        normalizeChannels(loadRawChannelPeaks(from: url, targetSampleCount: targetSampleCount))
    }

    static func loadRawPeaks(from url: URL, targetSampleCount: Int? = nil) -> [Float] {
        mix(loadRawChannelPeaks(from: url, targetSampleCount: targetSampleCount))
    }

    static func loadRawChannelPeaks(from url: URL, targetSampleCount: Int? = nil) -> [[Float]] {
        guard let decoder = PeakDecoder(url: url, targetSampleCount: targetSampleCount) else { return [] }
        var channels = decoder.makeBuckets()
        decoder.decode(0..<decoder.bucketCount, into: &channels)
        return channels
    }

    /// Loudest channel at each bucket. Mono files pass through unchanged.
    static func mix(_ channels: [[Float]]) -> [Float] {
        guard var mixed = channels.first else { return [] }
        for channel in channels.dropFirst() {
            let count = min(mixed.count, channel.count)
            for index in 0..<count {
                mixed[index] = max(mixed[index], channel[index])
            }
        }
        return mixed
    }

    static func normalizeChannels(_ channels: [[Float]]) -> [[Float]] {
        let peak = channels.flatMap { $0 }.max() ?? 0
        guard peak > 0 else { return channels }
        return channels.map { channel in channel.map { min(1, $0 / peak) } }
    }

    /// Number of peaks in the whole-file sketch shown before the full-density decode reaches a region.
    private static let previewSampleCount = 512
    /// Buckets decoded between progress checks while refining.
    private static let refineChunkBuckets = 512
    /// Minimum time between progressive updates, so redraws stay cheap.
    private static let progressInterval: TimeInterval = 0.2

    /// A cheap whole-file sketch of a waveform. It is available almost immediately and is
    /// replaced by real peaks, left to right, while the full-density decode runs.
    struct Preview: Sendable {
        let sampleCount: Int
        fileprivate let channelCount: Int
        fileprivate let coarse: [[Float]]
        fileprivate let estimatedMax: Float

        /// Full-length peaks per channel. `fine[..<decodedCount]` is real; the rest is the sketch.
        /// Every channel is scaled by the same maximum.
        fileprivate func compositeChannels(fine: [[Float]], decodedCount: Int) -> [[Float]] {
            let count = max(channelCount, 1)
            let decodedPeak = fine.flatMap { channel in channel.prefix(min(decodedCount, channel.count)) }.max() ?? 0
            let scaleMax = max(estimatedMax, decodedPeak)
            guard scaleMax > 0 else {
                return Array(repeating: [Float](repeating: 0, count: sampleCount), count: count)
            }

            return (0..<count).map { channel in
                let fineChannel = channel < fine.count ? fine[channel] : []
                let coarseChannel = channel < coarse.count ? coarse[channel] : []
                let decoded = min(decodedCount, fineChannel.count)
                return (0..<sampleCount).map { index in
                    let raw: Float
                    if index < decoded {
                        raw = fineChannel[index]
                    } else if coarseChannel.isEmpty {
                        raw = 0
                    } else {
                        raw = coarseChannel[min(coarseChannel.count - 1, index * coarseChannel.count / sampleCount)]
                    }
                    return min(1, raw / scaleMax)
                }
            }
        }

        func sketch() -> [Float] {
            mix(compositeChannels(fine: [], decodedCount: 0))
        }

        func channelSketch() -> [[Float]] {
            compositeChannels(fine: [], decodedCount: 0)
        }
    }

    static func loadPreview(from url: URL) -> Preview? {
        guard let fine = PeakDecoder(url: url, targetSampleCount: nil),
              let decoder = PeakDecoder(url: url, targetSampleCount: min(previewSampleCount, fine.bucketCount)) else {
            return nil
        }

        var coarse = decoder.makeBuckets()
        decoder.decode(0..<decoder.bucketCount, into: &coarse)
        let estimatedMax = coarse.flatMap { $0 }.max() ?? 0
        return Preview(
            sampleCount: fine.bucketCount,
            channelCount: fine.drawnChannelCount,
            coarse: coarse,
            estimatedMax: estimatedMax
        )
    }

    /// Decodes full-density, normalized peaks left to right, calling `onUpdate` with the
    /// partially refined waveform (real peaks so far, sketch for the rest) as it goes.
    static func refinePeaks(
        from url: URL,
        preview: Preview?,
        onUpdate: @Sendable ([Float]) -> Void
    ) -> [Float] {
        let channels = refineRawChannels(from: url, preview: preview) { partial in
            onUpdate(mix(partial))
        }
        return normalize(mix(channels))
    }

    /// Same decode as `refinePeaks`, keeping each channel. `onUpdate` receives normalized rows.
    static func refineChannelPeaks(
        from url: URL,
        preview: Preview?,
        onUpdate: @Sendable ([[Float]]) -> Void
    ) -> [[Float]] {
        normalizeChannels(refineRawChannels(from: url, preview: preview, onUpdate: onUpdate))
    }

    private static func refineRawChannels(
        from url: URL,
        preview: Preview?,
        onUpdate: @Sendable ([[Float]]) -> Void
    ) -> [[Float]] {
        guard let decoder = PeakDecoder(url: url, targetSampleCount: nil) else { return [] }

        var channels = decoder.makeBuckets()
        var decodedCount = 0
        var lastUpdate = Date()

        while decodedCount < decoder.bucketCount {
            let chunkEnd = min(decoder.bucketCount, decodedCount + refineChunkBuckets)
            guard decoder.decode(decodedCount..<chunkEnd, into: &channels) else { break }
            decodedCount = chunkEnd

            if decodedCount < decoder.bucketCount, let preview,
               Date().timeIntervalSince(lastUpdate) >= progressInterval {
                onUpdate(preview.compositeChannels(fine: channels, decodedCount: decodedCount))
                lastUpdate = Date()
            }
        }

        return channels
    }

    static func summedPeaks(
        from sources: [(url: URL, duration: TimeInterval)],
        targetSampleCount: Int? = nil
    ) -> [Float] {
        guard !sources.isEmpty else { return [] }

        let maxDuration = sources.map(\.duration).max() ?? 1
        guard maxDuration > 0 else { return [] }

        let perFile = sources.map { source -> (peaks: [Float], duration: TimeInterval) in
            (loadRawPeaks(from: source.url), source.duration)
        }
        return sumAlignedPeaks(perFile, maxDuration: maxDuration, targetSampleCount: targetSampleCount)
    }

    /// Merges already-decoded per-file peak overviews into one summed overview.
    static func sumAlignedPeaks(
        _ sources: [(peaks: [Float], duration: TimeInterval)],
        maxDuration: TimeInterval? = nil,
        targetSampleCount: Int? = nil
    ) -> [Float] {
        guard !sources.isEmpty else { return [] }

        let resolvedMaxDuration = maxDuration ?? sources.map(\.duration).max() ?? 1
        guard resolvedMaxDuration > 0 else { return [] }

        let bucketCount = targetSampleCount ?? overviewSampleCount(forDuration: resolvedMaxDuration)
        var summed = [Float](repeating: 0, count: bucketCount)

        for source in sources {
            guard !source.peaks.isEmpty, source.duration > 0 else { continue }

            for bucketIndex in 0..<bucketCount {
                let time = resolvedMaxDuration * (Double(bucketIndex) + 0.5) / Double(bucketCount)
                guard time < source.duration else { continue }

                let sourceIndex = Int((time / source.duration) * Double(source.peaks.count))
                let clampedIndex = min(max(0, sourceIndex), source.peaks.count - 1)
                summed[bucketIndex] += source.peaks[clampedIndex]
            }
        }

        return normalize(summed)
    }

    private static func normalize(_ peaks: [Float]) -> [Float] {
        guard let maxPeak = peaks.max(), maxPeak > 0 else { return peaks }
        return peaks.map { min(1, $0 / maxPeak) }
    }
}

/// Reads an audio file and reduces it to per-bucket peak amplitudes.
private final class PeakDecoder {
    /// Frames read per I/O call; also the largest window sampled for any one bucket.
    static let blockFrames = 32_768

    let bucketCount: Int
    let drawnChannelCount: Int

    private let file: AVAudioFile
    private let totalFrames: Int
    private let framesPerBucket: Int
    private let framesPerSample: Int
    private let buffer: AVAudioPCMBuffer
    private let converter: AVAudioConverter?
    private let inputBuffer: AVAudioPCMBuffer?

    convenience init?(url: URL, targetSampleCount: Int?) {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let requested = targetSampleCount ?? WaveformLoader.overviewSampleCount(forDuration: duration)
        self.init(file: file, requestedCount: requested)
    }

    init?(file: AVAudioFile, requestedCount: Int) {
        let totalFrames = Int(file.length)
        let bucketCount = min(requestedCount, totalFrames)
        let sourceFormat = file.processingFormat
        guard bucketCount > 0, sourceFormat.channelCount > 0 else { return nil }

        self.file = file
        self.totalFrames = totalFrames
        self.bucketCount = bucketCount
        drawnChannelCount = min(2, Int(sourceFormat.channelCount))
        framesPerBucket = max(1, totalFrames / bucketCount)
        // Sample a small window per bucket instead of scanning the entire file.
        // Cap the window so long stems (e.g. 79 min) stay seek-light.
        framesPerSample = min(framesPerBucket, totalFrames > 48_000 * 600 ? 2_048 : 8_192)

        let capacity = AVAudioFrameCount(Self.blockFrames)
        if sourceFormat.commonFormat == .pcmFormatFloat32 && !sourceFormat.isInterleaved {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity) else { return nil }
            self.buffer = buffer
            converter = nil
            inputBuffer = nil
        } else {
            guard let floatFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFormat.sampleRate,
                channels: sourceFormat.channelCount,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: floatFormat),
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity),
            let buffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: capacity) else {
                return nil
            }
            self.buffer = buffer
            self.converter = converter
            self.inputBuffer = inputBuffer
        }
    }

    func makeBuckets() -> [[Float]] {
        Array(repeating: [Float](repeating: 0, count: bucketCount), count: drawnChannelCount)
    }

    /// Fills each channel of `channels` over `range`. Returns false if the file stops yielding audio early.
    @discardableResult
    func decode(_ range: Range<Int>, into channels: inout [[Float]]) -> Bool {
        if framesPerSample >= framesPerBucket {
            // Every frame counts, so read contiguous blocks instead of seeking per bucket.
            let bucketsPerBlock = max(1, Self.blockFrames / framesPerBucket)
            var first = range.lowerBound

            while first < range.upperBound {
                let last = min(range.upperBound, first + bucketsPerBlock)
                let startFrame = first * framesPerBucket
                guard startFrame < totalFrames,
                      let block = read(startFrame: startFrame, frameCount: min(totalFrames - startFrame, (last - first) * framesPerBucket)) else {
                    return false
                }

                // AVAudioFile may return fewer frames than requested, so only consume the buckets
                // that were fully read and resume from there.
                let available = Int(block.frameLength)
                let covered = max(1, min(last - first, available / framesPerBucket))
                for offset in 0..<covered {
                    let from = offset * framesPerBucket
                    write(
                        channelPeaks(in: block, frames: from..<min(available, from + framesPerBucket)),
                        to: &channels,
                        bucket: first + offset
                    )
                }
                first += covered
            }
            return true
        }

        for bucket in range {
            let startFrame = bucket * framesPerBucket
            guard startFrame < totalFrames,
                  let block = read(startFrame: startFrame, frameCount: min(framesPerSample, totalFrames - startFrame)) else {
                return false
            }
            write(channelPeaks(in: block, frames: 0..<Int(block.frameLength)), to: &channels, bucket: bucket)
        }
        return true
    }

    private func write(_ values: [Float], to channels: inout [[Float]], bucket: Int) {
        for channel in 0..<min(values.count, channels.count) where bucket < channels[channel].count {
            channels[channel][bucket] = values[channel]
        }
    }

    private func read(startFrame: Int, frameCount: Int) -> AVAudioPCMBuffer? {
        file.framePosition = AVAudioFramePosition(startFrame)

        guard let converter, let inputBuffer else {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: AVAudioFrameCount(frameCount))) != nil,
                  buffer.frameLength > 0 else {
                return nil
            }
            return buffer
        }

        inputBuffer.frameLength = 0
        guard (try? file.read(into: inputBuffer, frameCount: AVAudioFrameCount(frameCount))) != nil,
              inputBuffer.frameLength > 0 else {
            return nil
        }

        converter.reset()
        buffer.frameLength = 0
        var conversionError: NSError?
        var didProvideInput = false
        let status = converter.convert(to: buffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, buffer.frameLength > 0 else { return nil }
        return buffer
    }

    /// Peak of each drawn channel. Extra channels past the second are left out.
    private func channelPeaks(in block: AVAudioPCMBuffer, frames: Range<Int>) -> [Float] {
        guard let channels = block.floatChannelData, !frames.isEmpty else {
            return [Float](repeating: 0, count: drawnChannelCount)
        }

        var peaks = [Float](repeating: 0, count: drawnChannelCount)
        let available = Int(block.format.channelCount)
        for channel in 0..<drawnChannelCount where channel < available {
            var channelPeak: Float = 0
            vDSP_maxmgv(channels[channel] + frames.lowerBound, 1, &channelPeak, vDSP_Length(frames.count))
            peaks[channel] = channelPeak
        }
        return peaks
    }
}
