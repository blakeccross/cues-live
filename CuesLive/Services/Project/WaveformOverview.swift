import AVFoundation
import Foundation

/// Multi-resolution min/max overview of one channel.
/// Level 0 is one block per 32 samples. Each level above merges 4 blocks of the level below.
struct WaveformOverview: Equatable, Sendable {
    static let block = 32
    static let fanout = 4

    struct Block: Equatable, Sendable {
        var min: Float
        var max: Float

        static let empty = Block(min: .infinity, max: -.infinity)

        static func point(_ sample: Float) -> Block {
            guard sample.isFinite else { return .empty }
            return Block(min: sample, max: sample)
        }

        static func of(_ samples: ArraySlice<Float>) -> Block {
            samples.reduce(.empty) { $0.merged(.point($1)) }
        }

        func merged(_ other: Block) -> Block {
            Block(min: Swift.min(min, other.min), max: Swift.max(max, other.max))
        }

        /// `(min, max)`, or `(0, 0)` when the block summed nothing.
        var range: (Float, Float) {
            min > max ? (0, 0) : (min, max)
        }
    }

    let sampleCount: Int
    /// `levels[0]` is the 32-sample blocks. Higher levels are built from it.
    let levels: [[Block]]

    init(sampleCount: Int, level0: [Block]) {
        self.sampleCount = sampleCount
        var levels = [level0]
        while let last = levels.last, last.count > 1 {
            var next: [Block] = []
            next.reserveCapacity((last.count + Self.fanout - 1) / Self.fanout)
            var index = 0
            while index < last.count {
                let end = min(last.count, index + Self.fanout)
                next.append(last[index..<end].reduce(.empty) { $0.merged($1) })
                index = end
            }
            levels.append(next)
        }
        self.levels = levels
    }

    static func build(_ samples: [Float]) -> WaveformOverview {
        guard !samples.isEmpty else { return WaveformOverview(sampleCount: 0, level0: []) }
        var level0: [Block] = []
        level0.reserveCapacity((samples.count + block - 1) / block)
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + block)
            level0.append(Block.of(samples[index..<end]))
            index = end
        }
        return WaveformOverview(sampleCount: samples.count, level0: level0)
    }

    /// Min and max of each column. Windows that miss the file are `nil`.
    /// Column `c` covers sample positions `[start + c * step, start + (c + 1) * step + overlap]`,
    /// expanded to the 32-sample blocks it touches so a peak is never dropped.
    func columns(start: Double, step: Double, overlap: Double = 0, count: Int) -> [(Float, Float)?] {
        guard sampleCount > 0, start.isFinite, step.isFinite, step > 0, overlap.isFinite, overlap >= 0, count > 0 else {
            return Array(repeating: nil, count: max(0, count))
        }
        let last = Double(sampleCount - 1)
        return (0..<count).map { column in
            let lower = start + step * Double(column)
            let upper = lower + step + overlap
            guard upper >= 0, lower <= last else { return nil }
            let from = max(0, Int(floor(max(lower, 0))))
            let to = min(sampleCount, Int(ceil(min(upper, last))) + 1)
            guard from < to else { return (0, 0) }
            return coveredRange(from: from, to: to)
        }
    }

    private func coveredRange(from start: Int, to end: Int) -> (Float, Float) {
        let end = min(end, sampleCount)
        let start = max(0, start)
        guard start < end else { return (0, 0) }
        let first = start / Self.block
        let last = (end + Self.block - 1) / Self.block
        return blocks(from: first, to: last).range
    }

    /// Level-0 blocks `[lo, hi)`, summed from the coarsest blocks that fit.
    private func blocks(from lower: Int, to upper: Int) -> Block {
        var lo = lower
        var hi = upper
        var accumulated = Block.empty
        for (levelIndex, level) in levels.enumerated() {
            func add(_ index: Int) {
                guard level.indices.contains(index) else { return }
                accumulated = accumulated.merged(level[index])
            }
            if levelIndex + 1 == levels.count || hi &- lo < 2 * Self.fanout {
                if lo < hi {
                    for index in lo..<hi { add(index) }
                }
                break
            }
            while lo % Self.fanout != 0 {
                add(lo)
                lo += 1
            }
            while hi % Self.fanout != 0 {
                hi -= 1
                add(hi)
            }
            lo /= Self.fanout
            hi /= Self.fanout
        }
        return accumulated
    }


    /// Exact min and max of each column over a slice of raw samples that starts at file frame
    /// `origin`, with the line between samples interpolated at the column edges so neighbouring
    /// columns stay connected. Returns `nil` when the slice does not cover the window; a column that
    /// misses the slice is `nil`. Column `c` covers `[windowStart + c * step, ... + step + overlap]`.
    static func sampleColumns(
        samples: [Float],
        origin: Int,
        fileEnd: Int,
        windowStart: Double,
        step: Double,
        overlap: Double,
        count: Int
    ) -> [(Float, Float)?]? {
        guard count > 0 else { return [] }
        guard windowStart.isFinite, step.isFinite, step > 0, overlap.isFinite, overlap >= 0 else { return nil }
        let lastFrame = windowStart + step * Double(count - 1) + step + overlap
        let neededStart = Int(floor(max(windowStart, 0)))
        let neededEnd = Int(ceil(min(lastFrame, Double(fileEnd))))
        guard neededStart >= origin, neededEnd <= origin + samples.count else { return nil }

        let local = { (frame: Double) -> Float? in
            let index = frame - Double(origin)
            let lower = Int(floor(index))
            guard lower >= 0, lower < samples.count else { return nil }
            let upper = min(samples.count - 1, lower + 1)
            let fraction = Float(index - Double(lower))
            let left = samples[lower]
            let right = samples[upper]
            return left + (right - left) * fraction
        }
        var columns: [(Float, Float)?] = []
        columns.reserveCapacity(count)
        for column in 0..<count {
            let lower = windowStart + step * Double(column)
            let upper = lower + step + overlap
            let from = Int(floor(lower)) - origin
            let to = Int(ceil(upper)) - origin
            guard to > from, from < samples.count, to > 0 else {
                columns.append(nil)
                continue
            }
            var minValue = Float.infinity
            var maxValue = -Float.infinity
            for edge in [local(lower), local(upper)] {
                if let edge, edge.isFinite {
                    minValue = Swift.min(minValue, edge)
                    maxValue = Swift.max(maxValue, edge)
                }
            }
            let startIndex = Swift.max(0, from)
            let endIndex = Swift.min(samples.count - 1, to)
            if startIndex <= endIndex {
                for sample in samples[startIndex...endIndex] where sample.isFinite {
                    minValue = Swift.min(minValue, sample)
                    maxValue = Swift.max(maxValue, sample)
                }
            }
            columns.append(minValue <= maxValue ? (minValue, maxValue) : nil)
        }
        return columns
    }
}

struct WaveformFileOverview: Equatable, Sendable {
    var sampleRate: Double
    var channels: [WaveformOverview]
    /// `false` when the file stopped decoding before its reported length. Such an overview is
    /// shown for the session but never written to the disk cache.
    var isComplete = true
}

enum WaveformOverviewBuilder {
    /// Scans every sample. The result keeps the min/max pyramid, not the samples.
    static func build(from url: URL) -> WaveformFileOverview? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let source = file.processingFormat
        let channelCount = min(2, Int(source.channelCount))
        let sampleRate = source.sampleRate
        let totalFrames = Int(file.length)
        guard channelCount > 0, sampleRate > 0, totalFrames > 0 else { return nil }

        let reader = SampleReader(file: file, source: source)
        guard let reader else { return nil }

        var level0 = Array(repeating: [WaveformOverview.Block](), count: channelCount)
        var running = Array(repeating: WaveformOverview.Block.empty, count: channelCount)
        var inBlock = 0
        let chunk = 65_536
        var frame = 0
        while frame < totalFrames {
            let count = min(chunk, totalFrames - frame)
            guard let buffer = reader.read(startFrame: frame, frameCount: count) else { break }
            let frames = Int(buffer.frameLength)
            guard let data = buffer.floatChannelData, frames > 0 else { break }
            let readable = min(channelCount, Int(buffer.format.channelCount))
            var index = 0
            while index < frames {
                let take = min(WaveformOverview.block - inBlock, frames - index)
                for channel in 0..<readable {
                    var low = running[channel].min
                    var high = running[channel].max
                    for sample in UnsafeBufferPointer(start: data[channel] + index, count: take) where sample.isFinite {
                        low = min(low, sample)
                        high = max(high, sample)
                    }
                    running[channel] = WaveformOverview.Block(min: low, max: high)
                }
                inBlock += take
                index += take
                if inBlock == WaveformOverview.block {
                    for channel in 0..<channelCount {
                        level0[channel].append(running[channel])
                        running[channel] = .empty
                    }
                    inBlock = 0
                }
            }
            frame += frames
        }
        if inBlock > 0 {
            for channel in 0..<channelCount {
                level0[channel].append(running[channel])
            }
        }
        guard frame > 0 else { return nil }
        let isComplete = frame >= totalFrames
        let channels = level0.map { WaveformOverview(sampleCount: frame, level0: $0) }
        return WaveformFileOverview(sampleRate: sampleRate, channels: channels, isComplete: isComplete)
    }

    /// The samples of one channel over `[startFrame, startFrame + count)`.
    static func samples(from url: URL, channel: Int, startFrame: Int, count: Int) -> [Float] {
        guard count > 0, channel >= 0,
              let file = try? AVAudioFile(forReading: url),
              let reader = SampleReader(file: file, source: file.processingFormat) else {
            return []
        }
        var result: [Float] = []
        result.reserveCapacity(count)
        var frame = max(0, startFrame)
        var remaining = count
        while remaining > 0 {
            guard let buffer = reader.read(startFrame: frame, frameCount: min(remaining, 65_536)),
                  let data = buffer.floatChannelData,
                  channel < Int(buffer.format.channelCount) else {
                break
            }
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            result.append(contentsOf: (0..<frames).map { data[channel][$0] })
            frame += frames
            remaining -= frames
        }
        return result
    }
}

/// Float, non-interleaved view of a file, converting when the file is not already in that form.
private final class SampleReader {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let converter: AVAudioConverter?
    private let inputBuffer: AVAudioPCMBuffer?

    init?(file: AVAudioFile, source: AVAudioFormat) {
        self.file = file
        let capacity = AVAudioFrameCount(65_536)
        if source.commonFormat == .pcmFormatFloat32 && !source.isInterleaved {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: capacity) else { return nil }
            self.buffer = buffer
            converter = nil
            inputBuffer = nil
        } else {
            guard let floatFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: source.sampleRate,
                channels: source.channelCount,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: source, to: floatFormat),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: capacity),
            let buffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: capacity) else {
                return nil
            }
            self.buffer = buffer
            self.converter = converter
            self.inputBuffer = input
        }
    }

    func read(startFrame: Int, frameCount: Int) -> AVAudioPCMBuffer? {
        guard frameCount > 0, startFrame < Int(file.length) else { return nil }
        file.framePosition = AVAudioFramePosition(startFrame)
        let requested = AVAudioFrameCount(min(frameCount, Int(buffer.frameCapacity)))

        guard let converter, let inputBuffer else {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: requested)) != nil, buffer.frameLength > 0 else {
                return nil
            }
            return buffer
        }

        inputBuffer.frameLength = 0
        guard (try? file.read(into: inputBuffer, frameCount: requested)) != nil, inputBuffer.frameLength > 0 else {
            return nil
        }
        converter.reset()
        buffer.frameLength = 0
        var didProvideInput = false
        var error: NSError?
        let status = converter.convert(to: buffer, error: &error) { _, outStatus in
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
}
