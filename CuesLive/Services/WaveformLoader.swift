import AVFoundation
import CryptoKit
import Foundation

enum WaveformLoader {
    /// High-resolution peak overview decoded once per audio file.
    static let overviewSampleCount = 4096

    static func loadPeaks(from url: URL, targetSampleCount: Int = overviewSampleCount) -> [Float] {
        normalize(loadRawPeaks(from: url, targetSampleCount: targetSampleCount))
    }

    static func loadRawPeaks(from url: URL, targetSampleCount: Int = overviewSampleCount) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              file.length > 0 else {
            return []
        }

        let totalFrames = Int(file.length)
        let bucketCount = min(targetSampleCount, totalFrames)
        guard bucketCount > 0 else { return [] }

        let framesPerBucket = max(1, totalFrames / bucketCount)
        // Sample a small window per bucket instead of scanning the entire file.
        let framesPerSample = min(framesPerBucket, 8_192)

        var peaks = [Float](repeating: 0, count: bucketCount)
        let sourceFormat = file.processingFormat
        let channelCount = Int(sourceFormat.channelCount)
        guard channelCount > 0 else { return [] }

        let canReadFloatDirectly =
            sourceFormat.commonFormat == .pcmFormatFloat32 && !sourceFormat.isInterleaved

        if canReadFloatDirectly {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(framesPerSample)
            ) else {
                return []
            }

            for bucketIndex in 0..<bucketCount {
                let startFrame = bucketIndex * framesPerBucket
                guard startFrame < totalFrames else { break }

                let readCount = min(framesPerSample, totalFrames - startFrame)
                file.framePosition = AVAudioFramePosition(startFrame)
                buffer.frameLength = 0

                guard (try? file.read(into: buffer, frameCount: AVAudioFrameCount(readCount))) != nil else {
                    break
                }

                peaks[bucketIndex] = peakAmplitude(in: buffer)
            }

            return Array(peaks.prefix(bucketCount))
        }

        guard let floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ),
        let converter = AVAudioConverter(from: sourceFormat, to: floatFormat),
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(framesPerSample)
        ),
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: floatFormat,
            frameCapacity: AVAudioFrameCount(framesPerSample)
        ) else {
            return []
        }

        for bucketIndex in 0..<bucketCount {
            let startFrame = bucketIndex * framesPerBucket
            guard startFrame < totalFrames else { break }

            let readCount = min(framesPerSample, totalFrames - startFrame)
            file.framePosition = AVAudioFramePosition(startFrame)
            inputBuffer.frameLength = 0

            guard (try? file.read(into: inputBuffer, frameCount: AVAudioFrameCount(readCount))) != nil,
                  inputBuffer.frameLength > 0 else {
                break
            }

            converter.reset()
            outputBuffer.frameLength = 0
            var conversionError: NSError?
            var didProvideInput = false
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if didProvideInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard status != .error, outputBuffer.frameLength > 0 else { break }
            peaks[bucketIndex] = peakAmplitude(in: outputBuffer)
        }

        return Array(peaks.prefix(bucketCount))
    }

    static func summedPeaks(
        from sources: [(url: URL, duration: TimeInterval)],
        targetSampleCount: Int = overviewSampleCount
    ) -> [Float] {
        guard !sources.isEmpty else { return [] }

        let maxDuration = sources.map(\.duration).max() ?? 1
        guard maxDuration > 0 else { return [] }

        let bucketCount = targetSampleCount
        var summed = [Float](repeating: 0, count: bucketCount)

        for source in sources {
            let rawPeaks = loadRawPeaks(from: source.url, targetSampleCount: targetSampleCount)
            guard !rawPeaks.isEmpty, source.duration > 0 else { continue }

            for bucketIndex in 0..<bucketCount {
                let time = maxDuration * (Double(bucketIndex) + 0.5) / Double(bucketCount)
                guard time < source.duration else { continue }

                let sourceIndex = Int((time / source.duration) * Double(rawPeaks.count))
                let clampedIndex = min(max(0, sourceIndex), rawPeaks.count - 1)
                summed[bucketIndex] += rawPeaks[clampedIndex]
            }
        }

        return normalize(summed)
    }

    private static func normalize(_ peaks: [Float]) -> [Float] {
        guard let maxPeak = peaks.max(), maxPeak > 0 else { return peaks }
        return peaks.map { min(1, $0 / maxPeak) }
    }

    private static func peakAmplitude(in buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        if let floatChannels = buffer.floatChannelData {
            return peakFromFloatChannels(floatChannels, frameLength: frameLength, channelCount: Int(buffer.format.channelCount))
        }

        if let int16Channels = buffer.int16ChannelData {
            return peakFromInt16Channels(int16Channels, frameLength: frameLength, channelCount: Int(buffer.format.channelCount))
        }

        if let int32Channels = buffer.int32ChannelData {
            return peakFromInt32Channels(int32Channels, frameLength: frameLength, channelCount: Int(buffer.format.channelCount))
        }

        return 0
    }

    private static func peakFromFloatChannels(
        _ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameLength: Int,
        channelCount: Int
    ) -> Float {
        var peak: Float = 0
        for channel in 0..<channelCount {
            let data = channels[channel]
            for frame in 0..<frameLength {
                peak = max(peak, abs(data[frame]))
            }
        }
        return peak
    }

    private static func peakFromInt16Channels(
        _ channels: UnsafePointer<UnsafeMutablePointer<Int16>>,
        frameLength: Int,
        channelCount: Int
    ) -> Float {
        var peak: Float = 0
        for channel in 0..<channelCount {
            let data = channels[channel]
            for frame in 0..<frameLength {
                peak = max(peak, abs(Float(data[frame]) / Float(Int16.max)))
            }
        }
        return peak
    }

    private static func peakFromInt32Channels(
        _ channels: UnsafePointer<UnsafeMutablePointer<Int32>>,
        frameLength: Int,
        channelCount: Int
    ) -> Float {
        let scale = Float(Int32(1 << 23))
        var peak: Float = 0
        for channel in 0..<channelCount {
            let data = channels[channel]
            for frame in 0..<frameLength {
                peak = max(peak, abs(Float(data[frame]) / scale))
            }
        }
        return peak
    }
}

enum WaveformPeakResampler {
    /// Upper bound on bars drawn per lane regardless of zoom level.
    static let maxDisplayBars = 1200
    /// Minimum horizontal spacing between bar centers in the song editor timeline.
    /// Two points per bar keeps scrolling smooth on long multi-track sessions.
    static let editorBarSlotWidth: CGFloat = 2
    /// Minimum horizontal spacing between bar centers when zoomed out (Voice Memos style).
    static let voiceMemosBarSlotWidth: CGFloat = 3

    static func displayPeaks(
        from source: [Float],
        contentWidth: CGFloat,
        minimumBarSlotWidth: CGFloat = editorBarSlotWidth
    ) -> [Float] {
        guard !source.isEmpty else { return [] }

        let requestedBars = requestedBarCount(for: contentWidth, minimumBarSlotWidth: minimumBarSlotWidth)
        let barCount = min(requestedBars, maxDisplayBars, source.count)
        guard barCount > 0 else { return [] }

        if barCount >= source.count {
            return source
        }

        var result = [Float](repeating: 0, count: barCount)
        let ratio = Double(source.count) / Double(barCount)

        for barIndex in 0..<barCount {
            let start = Int(Double(barIndex) * ratio)
            let end = min(source.count, max(start + 1, Int(Double(barIndex + 1) * ratio)))
            result[barIndex] = source[start..<end].max() ?? 0
        }

        return result
    }

    static func arrangedDisplayPeaks(
        from source: [Float],
        fileDuration: TimeInterval,
        sections: [ArrangementDisplaySection],
        timelineDuration: TimeInterval,
        contentWidth: CGFloat,
        minimumBarSlotWidth: CGFloat = editorBarSlotWidth
    ) -> [Float] {
        guard !source.isEmpty, fileDuration > 0, !sections.isEmpty else {
            return displayPeaks(
                from: source,
                contentWidth: contentWidth,
                minimumBarSlotWidth: minimumBarSlotWidth
            )
        }

        let safeTimelineDuration = max(timelineDuration, 0.001)
        let sortedSections = sections.sorted { $0.timelineStartSeconds < $1.timelineStartSeconds }

        let requestedBars = requestedBarCount(for: contentWidth, minimumBarSlotWidth: minimumBarSlotWidth)
        let barCount = min(requestedBars, maxDisplayBars)
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

    static func displayPeaks(
        from source: [Float],
        fileDuration: TimeInterval,
        sections: [ArrangementDisplaySection],
        timelineDuration: TimeInterval,
        timeRange: ClosedRange<TimeInterval>,
        contentWidth: CGFloat,
        minimumBarSlotWidth: CGFloat = voiceMemosBarSlotWidth
    ) -> [Float] {
        guard !source.isEmpty else { return [] }

        let barCount = min(
            requestedBarCount(for: contentWidth, minimumBarSlotWidth: minimumBarSlotWidth),
            maxDisplayBars
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

    func peaks(for url: URL) async -> [Float] {
        if let cached = cachedPeaks(for: url) {
            return cached
        }

        let key = Self.peakKey(for: url)

        if let existingTask = inflightTasks[key] {
            return await existingTask.value
        }

        let task = Task.detached(priority: .utility) { () -> [Float] in
            await WaveformPeakLoadLimiter.shared.acquire()
            defer { Task { await WaveformPeakLoadLimiter.shared.release() } }

            let peaks = WaveformLoader.loadPeaks(from: url)
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

        let task = Task.detached(priority: .utility) { () -> [Float] in
            await WaveformPeakLoadLimiter.shared.acquire()
            defer { Task { await WaveformPeakLoadLimiter.shared.release() } }

            let peaks = WaveformLoader.summedPeaks(from: sources)
            WaveformPeakDiskCache.save(peaks, forKey: key)
            await WaveformCache.shared.store(peaks, forKey: key)
            return peaks
        }

        inflightTasks[key] = task
        let peaks = await task.value
        inflightTasks[key] = nil
        return peaks
    }

    private func store(_ peaks: [Float], forKey key: String) {
        peakCache[key] = peaks
    }

    private static func peakKey(for url: URL) -> String {
        let modificationDate = fileModificationTimestamp(for: url)
        return "\(url.path)|\(modificationDate)|\(WaveformLoader.overviewSampleCount)"
    }

    private static func summedPeakKey(for sources: [(url: URL, duration: TimeInterval)]) -> String {
        let parts = sources
            .sorted { $0.url.path < $1.url.path }
            .map { "\($0.url.path)|\(fileModificationTimestamp(for: $0.url))|\($0.duration)" }
        return "sum|\(parts.joined(separator: ";"))|\(WaveformLoader.overviewSampleCount)"
    }

    private static func fileModificationTimestamp(for url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values?.contentModificationDate else { return 0 }
        return Int(date.timeIntervalSince1970)
    }
}

private enum WaveformPeakLoadLimiter {
    static let shared = PeakLoadLimiter(maxConcurrent: 1)
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
