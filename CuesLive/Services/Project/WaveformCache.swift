import AVFoundation
import Foundation

@MainActor
final class WaveformCache {
    static let shared = WaveformCache()

    private var peakCache: [String: [Float]] = [:]
    private var channelCache: [String: [[Float]]] = [:]
    private var inflightTasks: [String: Task<[Float], Never>] = [:]
    private var channelInflightTasks: [String: Task<[[Float]], Never>] = [:]
    private var overviewCache: [String: WaveformFileOverview] = [:]
    private var overviewInflightTasks: [String: Task<WaveformFileOverview, Never>] = [:]
    private var minMaxCache: [String: WaveformMinMax] = [:]
    private var minMaxInflight: [String: Task<WaveformMinMax, Never>] = [:]
    private var partialPeaks: [String: [Float]] = [:]
    private var partialChannels: [String: [[Float]]] = [:]
    private var progressHandlers: [String: [UUID: @MainActor ([Float]) -> Void]] = [:]
    private var channelProgressHandlers: [String: [UUID: @MainActor ([[Float]]) -> Void]] = [:]

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

    func cachedChannelPeaks(for url: URL) -> [[Float]]? {
        let key = Self.peakKey(for: url)
        if let cached = channelCache[key] {
            return cached
        }
        if let diskPeaks = WaveformPeakDiskCache.loadChannels(forKey: key) {
            channelCache[key] = diskPeaks
            return diskPeaks
        }
        return nil
    }

    /// Per-channel peaks for `url`. A stereo file yields two rows that share one level scale.
    func channelPeaks(for url: URL, onProgress: (@MainActor ([[Float]]) -> Void)? = nil) async -> [[Float]] {
        if let cached = cachedChannelPeaks(for: url) {
            return cached
        }

        let key = Self.peakKey(for: url)
        let handlerID = UUID()
        if let onProgress {
            channelProgressHandlers[key, default: [:]][handlerID] = onProgress
            if let partial = partialChannels[key] {
                onProgress(partial)
            }
        }
        defer { channelProgressHandlers[key]?[handlerID] = nil }

        if let existingTask = channelInflightTasks[key] {
            return await existingTask.value
        }

        let task = Task.detached(priority: .utility) { () -> [[Float]] in
            let preview = WaveformLoader.loadPreview(from: url)
            if let preview {
                await WaveformCache.shared.publishPartialChannels(preview.channelSketch(), forKey: key)
            }

            await WaveformPeakLoadLimiter.shared.acquire()
            defer { Task { await WaveformPeakLoadLimiter.shared.release() } }

            let channels = WaveformLoader.refineChannelPeaks(from: url, preview: preview) { partial in
                Task { @MainActor in
                    WaveformCache.shared.publishPartialChannels(partial, forKey: key)
                }
            }
            WaveformPeakDiskCache.saveChannels(channels, forKey: key)
            let mixed = WaveformLoader.mix(channels)
            WaveformPeakDiskCache.save(mixed, forKey: key)
            await WaveformCache.shared.storeChannels(channels, mixed: mixed, forKey: key)
            return channels
        }

        channelInflightTasks[key] = task
        let channels = await task.value
        channelInflightTasks[key] = nil
        return channels
    }

    func cachedOverview(for url: URL) -> WaveformFileOverview? {
        let key = Self.peakKey(for: url)
        if let cached = overviewCache[key] {
            return cached
        }
        if let disk = WaveformPeakDiskCache.loadOverview(forKey: key) {
            overviewCache[key] = disk
            return disk
        }
        return nil
    }

    /// Min/max overview of each channel. The samples themselves are not kept.
    func overview(for url: URL) async -> WaveformFileOverview {
        if let cached = cachedOverview(for: url) {
            return cached
        }
        let key = Self.peakKey(for: url)
        if let existing = overviewInflightTasks[key] {
            return await existing.value
        }
        let task = Task.detached(priority: .utility) { () -> WaveformFileOverview in
            await WaveformPeakLoadLimiter.shared.acquire()
            defer { Task { await WaveformPeakLoadLimiter.shared.release() } }
            let overview = WaveformOverviewBuilder.build(from: url) ?? WaveformFileOverview(sampleRate: 0, channels: [])
            if !overview.channels.isEmpty, overview.isComplete {
                WaveformPeakDiskCache.saveOverview(overview, forKey: key)
            }
            await WaveformCache.shared.storeOverview(overview, forKey: key)
            return overview
        }
        overviewInflightTasks[key] = task
        let overview = await task.value
        overviewInflightTasks[key] = nil
        return overview
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

    /// Summed min/max built from the same per-file overviews the editor draws.
    /// Cached for the session; the overviews themselves stay on disk.
    func summedMinMax(for sources: [(url: URL, duration: TimeInterval)]) async -> WaveformMinMax {
        guard !sources.isEmpty else { return .empty }
        let key = Self.summedPeakKey(for: sources)
        if let cached = minMaxCache[key] { return cached }
        if let existing = minMaxInflight[key] { return await existing.value }

        let task = Task { @MainActor () -> WaveformMinMax in
            var ordered = Array(
                repeating: (overview: WaveformFileOverview(sampleRate: 0, channels: []), duration: 0.0),
                count: sources.count
            )
            await withTaskGroup(of: (Int, WaveformFileOverview, TimeInterval).self) { group in
                for (index, source) in sources.enumerated() {
                    let url = source.url
                    let duration = source.duration
                    group.addTask {
                        let overview = await WaveformCache.shared.overview(for: url)
                        return (index, overview, duration)
                    }
                }
                for await (index, overview, duration) in group {
                    ordered[index] = (overview: overview, duration: duration)
                }
            }
            return await Task.detached(priority: .utility) {
                WaveformPeakResampler.summedMinMax(from: ordered)
            }.value
        }
        minMaxInflight[key] = task
        let series = await task.value
        minMaxInflight[key] = nil
        if !series.isEmpty {
            minMaxCache[key] = series
        }
        return series
    }

    private func store(_ peaks: [Float], forKey key: String) {
        peakCache[key] = peaks
        partialPeaks[key] = nil
    }

    private func storeOverview(_ overview: WaveformFileOverview, forKey key: String) {
        guard !overview.channels.isEmpty else { return }
        overviewCache[key] = overview
    }

    private func storeChannels(_ channels: [[Float]], mixed: [Float], forKey key: String) {
        channelCache[key] = channels
        partialChannels[key] = nil
        if peakCache[key] == nil {
            peakCache[key] = mixed
            partialPeaks[key] = nil
        }
    }

    private func publishPartialChannels(_ channels: [[Float]], forKey key: String) {
        guard channelCache[key] == nil else { return }
        partialChannels[key] = channels
        for handler in channelProgressHandlers[key]?.values ?? [:].values {
            handler(channels)
        }
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
