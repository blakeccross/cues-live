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

    static func loadRawPeaks(from url: URL, targetSampleCount: Int? = nil) -> [Float] {
        guard let decoder = PeakDecoder(url: url, targetSampleCount: targetSampleCount) else { return [] }
        var peaks = [Float](repeating: 0, count: decoder.bucketCount)
        decoder.decode(0..<decoder.bucketCount, into: &peaks)
        return peaks
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
        fileprivate let coarse: [Float]
        fileprivate let estimatedMax: Float

        /// Full-length peaks with `fine[..<decodedCount]` real and the rest filled from the sketch.
        fileprivate func composite(fine: [Float], decodedCount: Int) -> [Float] {
            let decoded = min(decodedCount, fine.count)
            let scaleMax = max(estimatedMax, fine.prefix(decoded).max() ?? 0)
            guard scaleMax > 0, !coarse.isEmpty else { return [Float](repeating: 0, count: fine.count) }

            return (0..<fine.count).map { index in
                let raw = index < decoded
                    ? fine[index]
                    : coarse[min(coarse.count - 1, index * coarse.count / fine.count)]
                return min(1, raw / scaleMax)
            }
        }

        func sketch() -> [Float] {
            composite(fine: [Float](repeating: 0, count: sampleCount), decodedCount: 0)
        }
    }

    static func loadPreview(from url: URL) -> Preview? {
        guard let fine = PeakDecoder(url: url, targetSampleCount: nil),
              let decoder = PeakDecoder(url: url, targetSampleCount: min(previewSampleCount, fine.bucketCount)) else {
            return nil
        }

        var coarse = [Float](repeating: 0, count: decoder.bucketCount)
        decoder.decode(0..<decoder.bucketCount, into: &coarse)
        return Preview(sampleCount: fine.bucketCount, coarse: coarse, estimatedMax: coarse.max() ?? 0)
    }

    /// Decodes full-density, normalized peaks left to right, calling `onUpdate` with the
    /// partially refined waveform (real peaks so far, sketch for the rest) as it goes.
    static func refinePeaks(
        from url: URL,
        preview: Preview?,
        onUpdate: @Sendable ([Float]) -> Void
    ) -> [Float] {
        guard let decoder = PeakDecoder(url: url, targetSampleCount: nil) else { return [] }

        let bucketCount = decoder.bucketCount
        var peaks = [Float](repeating: 0, count: bucketCount)
        var decodedCount = 0
        var lastUpdate = Date()

        while decodedCount < bucketCount {
            let chunkEnd = min(bucketCount, decodedCount + refineChunkBuckets)
            guard decoder.decode(decodedCount..<chunkEnd, into: &peaks) else { break }
            decodedCount = chunkEnd

            if decodedCount < bucketCount, let preview,
               Date().timeIntervalSince(lastUpdate) >= progressInterval {
                onUpdate(preview.composite(fine: peaks, decodedCount: decodedCount))
                lastUpdate = Date()
            }
        }

        return normalize(peaks)
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

    /// Fills `peaks[range]`. Returns false if the file stops yielding audio early.
    @discardableResult
    func decode(_ range: Range<Int>, into peaks: inout [Float]) -> Bool {
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
                    peaks[first + offset] = peak(in: block, frames: from..<min(available, from + framesPerBucket))
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
            peaks[bucket] = peak(in: block, frames: 0..<Int(block.frameLength))
        }
        return true
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

    private func peak(in block: AVAudioPCMBuffer, frames: Range<Int>) -> Float {
        guard let channels = block.floatChannelData, !frames.isEmpty else { return 0 }

        var peak: Float = 0
        for channel in 0..<Int(block.format.channelCount) {
            var channelPeak: Float = 0
            vDSP_maxmgv(channels[channel] + frames.lowerBound, 1, &channelPeak, vDSP_Length(frames.count))
            peak = max(peak, channelPeak)
        }
        return peak
    }
}

enum WaveformPeakResampler {
    /// Upper bound on bars for the song-editor timeline (long sessions stay scrollable).
    /// Setlist / Voice Memos paths pass `maximumBars: nil` so density stays fixed by slot width.
    static let maxDisplayBars = 32_768
    /// Minimum horizontal spacing between bar centers in the song editor timeline.
    /// One point per bar gives a finely detailed envelope; the display cap keeps long sessions scrollable.
    static let editorBarSlotWidth: CGFloat = 1
    /// Minimum horizontal spacing between bar centers when zoomed out (Voice Memos style).
    static let voiceMemosBarSlotWidth: CGFloat = 3

    static func displayPeaks(
        from source: [Float],
        contentWidth: CGFloat,
        minimumBarSlotWidth: CGFloat = editorBarSlotWidth,
        maximumBars: Int? = maxDisplayBars
    ) -> [Float] {
        guard !source.isEmpty else { return [] }

        // Bars beyond the overview density add no detail, so never exceed it.
        let barCount = min(
            source.count,
            resolvedBarCount(
                contentWidth: contentWidth,
                minimumBarSlotWidth: minimumBarSlotWidth,
                maximumBars: maximumBars
            )
        )
        guard barCount > 0 else { return [] }

        var result = [Float](repeating: 0, count: barCount)
        let ratio = Double(source.count) / Double(barCount)

        if ratio >= 1 {
            // Source denser than display: max-downsample each slot.
            for barIndex in 0..<barCount {
                let start = Int(Double(barIndex) * ratio)
                let end = min(source.count, max(start + 1, Int(Double(barIndex + 1) * ratio)))
                result[barIndex] = source[start..<end].max() ?? 0
            }
        } else {
            // Display denser than source: hold each overview sample across slots so
            // long lanes keep the same ~3pt candle spacing as short ones.
            for barIndex in 0..<barCount {
                let sourceIndex = min(
                    source.count - 1,
                    Int(Double(barIndex) * Double(source.count) / Double(barCount))
                )
                result[barIndex] = source[sourceIndex]
            }
        }

        return result
    }

    static func arrangedDisplayPeaks(
        from source: [Float],
        fileDuration: TimeInterval,
        sections: [ArrangementDisplaySection],
        timelineDuration: TimeInterval,
        contentWidth: CGFloat,
        minimumBarSlotWidth: CGFloat = editorBarSlotWidth,
        maximumBars: Int? = maxDisplayBars
    ) -> [Float] {
        guard !source.isEmpty, fileDuration > 0, !sections.isEmpty else {
            return displayPeaks(
                from: source,
                contentWidth: contentWidth,
                minimumBarSlotWidth: minimumBarSlotWidth,
                maximumBars: maximumBars
            )
        }

        let safeTimelineDuration = max(timelineDuration, 0.001)
        let sortedSections = sections.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }

        let barCount = min(
            source.count,
            resolvedBarCount(
                contentWidth: contentWidth,
                minimumBarSlotWidth: minimumBarSlotWidth,
                maximumBars: maximumBars
            )
        )
        guard barCount > 0 else { return [] }

        var result = [Float](repeating: 0, count: barCount)

        for barIndex in 0..<barCount {
            let arrangementTime = safeTimelineDuration * (Double(barIndex) + 0.5) / Double(barCount)
            guard let section = section(containing: arrangementTime, in: sortedSections) else {
                continue
            }

            let sourceTime = section.sourceStartSeconds + (arrangementTime - section.timelineStartSeconds)
            let sourceIndex = Int((sourceTime / fileDuration) * Double(source.count))
            let clampedIndex = min(max(0, sourceIndex), source.count - 1)
            result[barIndex] = source[clampedIndex]
        }

        return result
    }

    /// Collapses `peaks` into consecutive groups of `groupSize`, keeping each group's maximum.
    /// `groups` are group indices; ones that start past the end of `peaks` are omitted.
    static func groupedMaxima(
        of peaks: [Float],
        groupSize: Int,
        groups: ClosedRange<Int>
    ) -> [Float] {
        let size = max(1, groupSize)
        return groups.compactMap { group in
            let start = group * size
            guard start >= 0, start < peaks.count else { return nil }
            return peaks[start..<min(start + size, peaks.count)].max()
        }
    }

    /// Lays source peaks on the timeline at the source's own resolution.
    /// The result does not depend on view width, so zoom scales this shape instead of rebuilding it.
    static func timelinePeaks(
        from source: [Float],
        fileDuration: TimeInterval,
        sections: [ArrangementDisplaySection],
        timelineDuration: TimeInterval
    ) -> [Float] {
        guard !source.isEmpty else { return [] }
        guard fileDuration > 0, !sections.isEmpty else { return source }

        let safeTimelineDuration = max(timelineDuration, 0.001)
        let sortedSections = sections.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        let sampleCount = source.count
        var result = [Float](repeating: 0, count: sampleCount)

        for index in 0..<sampleCount {
            let arrangementTime = safeTimelineDuration * (Double(index) + 0.5) / Double(sampleCount)
            guard let section = section(containing: arrangementTime, in: sortedSections) else {
                continue
            }

            let sourceTime = section.sourceStartSeconds + (arrangementTime - section.timelineStartSeconds)
            let sourceIndex = Int((sourceTime / fileDuration) * Double(source.count))
            let clampedIndex = min(max(0, sourceIndex), source.count - 1)
            result[index] = source[clampedIndex]
        }

        return result
    }

    static func displayPeaks(
        from source: [Float],
        fileDuration: TimeInterval,
        sections: [ArrangementDisplaySection],
        timelineDuration: TimeInterval,
        timeRange: ClosedRange<TimeInterval>,
        contentWidth: CGFloat,
        minimumBarSlotWidth: CGFloat = voiceMemosBarSlotWidth,
        maximumBars: Int? = nil
    ) -> [Float] {
        guard !source.isEmpty else { return [] }

        let barCount = resolvedBarCount(
            contentWidth: contentWidth,
            minimumBarSlotWidth: minimumBarSlotWidth,
            maximumBars: maximumBars
        )
        guard barCount > 0 else { return [] }

        let rangeDuration = max(timeRange.upperBound - timeRange.lowerBound, 0.001)
        let safeTimelineDuration = max(timelineDuration, 0.001)
        let sortedSections = sections.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }
        let usesArrangement = fileDuration > 0 && !sortedSections.isEmpty

        var result = [Float](repeating: 0, count: barCount)

        for barIndex in 0..<barCount {
            let timelineTime = timeRange.lowerBound
                + rangeDuration * (Double(barIndex) + 0.5) / Double(barCount)

            if usesArrangement, let section = section(containing: timelineTime, in: sortedSections) {
                let sourceTime = section.sourceStartSeconds + (timelineTime - section.timelineStartSeconds)
                let sourceIndex = Int((sourceTime / fileDuration) * Double(source.count))
                let clampedIndex = min(max(0, sourceIndex), source.count - 1)
                result[barIndex] = source[clampedIndex]
            } else {
                let fraction = min(max(timelineTime / safeTimelineDuration, 0), 1)
                let sourceIndex = Int(fraction * Double(source.count))
                let clampedIndex = min(max(0, sourceIndex), source.count - 1)
                result[barIndex] = source[clampedIndex]
            }
        }

        return result
    }

    /// Extracts the display-peak slice for a timeline range from a full-lane peak array.
    static func peaksSlice(
        from bars: [Float],
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval,
        timelineDuration: TimeInterval
    ) -> [Float] {
        guard !bars.isEmpty, timelineEnd > timelineStart else { return [] }

        let safeDuration = max(timelineDuration, 0.001)
        let count = bars.count
        let startIndex = min(
            count - 1,
            max(0, Int(floor(timelineStart / safeDuration * Double(count))))
        )
        let endIndex = min(
            count,
            max(startIndex + 1, Int(ceil(timelineEnd / safeDuration * Double(count))))
        )
        guard startIndex < endIndex else { return [] }
        return Array(bars[startIndex..<endIndex])
    }

    private static func resolvedBarCount(
        contentWidth: CGFloat,
        minimumBarSlotWidth: CGFloat,
        maximumBars: Int?
    ) -> Int {
        let requested = requestedBarCount(for: contentWidth, minimumBarSlotWidth: minimumBarSlotWidth)
        guard let maximumBars else { return requested }
        return min(requested, max(1, maximumBars))
    }

    private static func requestedBarCount(for contentWidth: CGFloat, minimumBarSlotWidth: CGFloat) -> Int {
        let slotWidth = max(1, minimumBarSlotWidth)
        return max(1, Int((contentWidth / slotWidth).rounded()))
    }

    private static func section(
        containing time: TimeInterval,
        in sections: [ArrangementDisplaySection]
    ) -> ArrangementDisplaySection? {
        guard !sections.isEmpty else { return nil }

        var low = 0
        var high = sections.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let candidate = sections[mid]

            if time < candidate.timelineStartSeconds {
                high = mid - 1
            } else if time >= candidate.timelineEndSeconds {
                low = mid + 1
            } else {
                return candidate
            }
        }

        return nil
    }
}

enum WaveformPeakDiskCache {
    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("WaveformPeaks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load(forKey key: String) -> [Float]? {
        let url = cacheDirectory.appendingPathComponent(fileName(for: key))
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            return nil
        }

        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    static func save(_ peaks: [Float], forKey key: String) {
        let url = cacheDirectory.appendingPathComponent(fileName(for: key))
        peaks.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            let data = Data(buffer: UnsafeBufferPointer(start: base, count: buffer.count))
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).peaks"
    }
}

@MainActor
final class WaveformCache {
    static let shared = WaveformCache()

    private var peakCache: [String: [Float]] = [:]
    private var inflightTasks: [String: Task<[Float], Never>] = [:]
    private var partialPeaks: [String: [Float]] = [:]
    private var progressHandlers: [String: [UUID: @MainActor ([Float]) -> Void]] = [:]

    func cachedPeaks(for url: URL) -> [Float]? {
        let key = Self.peakKey(for: url)

        if let cached = peakCache[key] {
            return cached
        }

        if let diskPeaks = WaveformPeakDiskCache.load(forKey: key) {
            peakCache[key] = diskPeaks
            return diskPeaks
        }

        return nil
    }

    /// Returns the full peaks for `url`. While they decode, `onProgress` receives a whole-file
    /// sketch first, then progressively sharper versions, so lanes can draw immediately.
    func peaks(for url: URL, onProgress: (@MainActor ([Float]) -> Void)? = nil) async -> [Float] {
        if let cached = cachedPeaks(for: url) {
            return cached
        }

        let key = Self.peakKey(for: url)

        let handlerID = UUID()
        if let onProgress {
            progressHandlers[key, default: [:]][handlerID] = onProgress
            if let partial = partialPeaks[key] {
                onProgress(partial)
            }
        }
        defer { progressHandlers[key]?[handlerID] = nil }

        if let existingTask = inflightTasks[key] {
            return await existingTask.value
        }

        let task = Task.detached(priority: .utility) { () -> [Float] in
            // The sketch is cheap, so it skips the limiter and every lane gets a shape right away.
            let preview = WaveformLoader.loadPreview(from: url)
            if let preview {
                await WaveformCache.shared.publishPartial(preview.sketch(), forKey: key)
            }

            await WaveformPeakLoadLimiter.shared.acquire()
            defer { Task { await WaveformPeakLoadLimiter.shared.release() } }

            let peaks = WaveformLoader.refinePeaks(from: url, preview: preview) { partial in
                Task { @MainActor in
                    WaveformCache.shared.publishPartial(partial, forKey: key)
                }
            }
            WaveformPeakDiskCache.save(peaks, forKey: key)
            await WaveformCache.shared.store(peaks, forKey: key)
            return peaks
        }

        inflightTasks[key] = task
        let peaks = await task.value
        inflightTasks[key] = nil
        return peaks
    }

    func cachedSummedPeaks(for sources: [(url: URL, duration: TimeInterval)]) -> [Float]? {
        let key = Self.summedPeakKey(for: sources)

        if let cached = peakCache[key] {
            return cached
        }

        if let diskPeaks = WaveformPeakDiskCache.load(forKey: key) {
            peakCache[key] = diskPeaks
            return diskPeaks
        }

        return nil
    }

    func summedPeaks(for sources: [(url: URL, duration: TimeInterval)]) async -> [Float] {
        if let cached = cachedSummedPeaks(for: sources) {
            return cached
        }

        let key = Self.summedPeakKey(for: sources)

        if let existingTask = inflightTasks[key] {
            return await existingTask.value
        }

        // Snapshot per-file keys on the main actor, then decode misses off-main.
        let fileJobs: [(index: Int, url: URL, duration: TimeInterval, cacheKey: String, cached: [Float]?)] =
            sources.enumerated().map { index, source in
                let cacheKey = Self.peakKey(for: source.url)
                return (index, source.url, source.duration, cacheKey, cachedPeaks(for: source.url))
            }

        let task = Task.detached(priority: .utility) { () -> [Float] in
            var ordered = Array(
                repeating: (peaks: [Float](), duration: 0.0),
                count: fileJobs.count
            )

            await withTaskGroup(of: (Int, [Float], TimeInterval).self) { group in
                for job in fileJobs {
                    group.addTask {
                        if let cached = job.cached {
                            return (job.index, cached, job.duration)
                        }

                        await WaveformPeakLoadLimiter.shared.acquire()
                        let peaks: [Float]
                        defer { Task { await WaveformPeakLoadLimiter.shared.release() } }

                        if let diskPeaks = WaveformPeakDiskCache.load(forKey: job.cacheKey) {
                            peaks = diskPeaks
                        } else {
                            peaks = WaveformLoader.loadPeaks(from: job.url)
                            WaveformPeakDiskCache.save(peaks, forKey: job.cacheKey)
                        }
                        return (job.index, peaks, job.duration)
                    }
                }

                for await (index, peaks, duration) in group {
                    ordered[index] = (peaks, duration)
                }
            }

            let summed = WaveformLoader.sumAlignedPeaks(ordered)
            WaveformPeakDiskCache.save(summed, forKey: key)
            await WaveformCache.shared.store(summed, forKey: key)
            for job in fileJobs where job.cached == nil {
                let peaks = ordered[job.index].peaks
                guard !peaks.isEmpty else { continue }
                await WaveformCache.shared.store(peaks, forKey: job.cacheKey)
            }
            return summed
        }

        inflightTasks[key] = task
        let peaks = await task.value
        inflightTasks[key] = nil
        return peaks
    }

    private func store(_ peaks: [Float], forKey key: String) {
        peakCache[key] = peaks
        partialPeaks[key] = nil
    }

    private func publishPartial(_ peaks: [Float], forKey key: String) {
        // A late partial must never overwrite the finished result.
        guard peakCache[key] == nil else { return }
        partialPeaks[key] = peaks
        for handler in progressHandlers[key]?.values ?? [:].values {
            handler(peaks)
        }
    }

    private static func peakKey(for url: URL) -> String {
        let modificationDate = fileModificationTimestamp(for: url)
        return "\(url.path)|\(modificationDate)|v\(WaveformLoader.overviewVersion)"
    }

    private static func summedPeakKey(for sources: [(url: URL, duration: TimeInterval)]) -> String {
        let parts = sources
            .sorted { $0.url.path < $1.url.path }
            .map { "\($0.url.path)|\(fileModificationTimestamp(for: $0.url))|\($0.duration)" }
        return "sum|\(parts.joined(separator: ";"))|v\(WaveformLoader.overviewVersion)"
    }

    private static func fileModificationTimestamp(for url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values?.contentModificationDate else { return 0 }
        return Int(date.timeIntervalSince1970)
    }
}

private enum WaveformPeakLoadLimiter {
    static let shared = PeakLoadLimiter(maxConcurrent: 4)
}

private actor PeakLoadLimiter {
    private let maxConcurrent: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        activeCount += 1
    }

    func release() {
        activeCount = max(0, activeCount - 1)
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        }
    }
}
