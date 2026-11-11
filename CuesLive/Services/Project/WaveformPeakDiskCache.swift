import CryptoKit
import Foundation

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

    static func loadChannels(forKey key: String) -> [[Float]]? {
        let url = cacheDirectory.appendingPathComponent(channelFileName(for: key))
        guard let data = try? Data(contentsOf: url), data.count >= 8 else { return nil }
        let channelCount = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) })
        let length = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
        let stride = MemoryLayout<Float>.stride
        guard channelCount >= 1, channelCount <= 2, length > 0,
              data.count == 8 + channelCount * length * stride else {
            return nil
        }
        return (0..<channelCount).map { channel in
            let start = 8 + channel * length * stride
            let slice = data.subdata(in: start..<(start + length * stride))
            return slice.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        }
    }

    static func saveChannels(_ channels: [[Float]], forKey key: String) {
        guard let length = channels.first?.count, length > 0,
              channels.count <= 2,
              channels.allSatisfy({ $0.count == length }) else {
            return
        }
        var data = Data()
        var channelCount = UInt32(channels.count)
        var bucketCount = UInt32(length)
        data.append(Data(bytes: &channelCount, count: 4))
        data.append(Data(bytes: &bucketCount, count: 4))
        for channel in channels {
            channel.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                data.append(Data(buffer: UnsafeBufferPointer(start: base, count: buffer.count)))
            }
        }
        let url = cacheDirectory.appendingPathComponent(channelFileName(for: key))
        try? data.write(to: url, options: .atomic)
    }

    static func loadOverview(forKey key: String) -> WaveformFileOverview? {
        let url = cacheDirectory.appendingPathComponent(overviewFileName(for: key))
        guard let data = try? Data(contentsOf: url), data.count >= 24 else { return nil }
        let magic: UInt32 = readValue(data, at: 0)
        guard magic == 0x574F_5631 else { return nil }
        let channelCount = Int(readValue(data, at: 4) as UInt32)
        let sampleRate = Double(readValue(data, at: 8) as Float64)
        let sampleCount = Int(readValue(data, at: 16) as UInt64)
        guard channelCount >= 1, channelCount <= 2, sampleRate > 0, sampleCount > 0 else { return nil }

        var offset = 24
        var channels: [WaveformOverview] = []
        let stride = MemoryLayout<Float>.stride
        for _ in 0..<channelCount {
            guard offset + 4 <= data.count else { return nil }
            let blockCount = Int(readValue(data, at: offset) as UInt32)
            offset += 4
            let bytes = blockCount * 2 * stride
            guard blockCount > 0, offset + bytes <= data.count else { return nil }
            let slice = data.subdata(in: offset..<(offset + bytes))
            let floats = slice.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            guard floats.count == blockCount * 2 else { return nil }
            var blocks: [WaveformOverview.Block] = []
            blocks.reserveCapacity(blockCount)
            var index = 0
            while index < floats.count {
                blocks.append(WaveformOverview.Block(min: floats[index], max: floats[index + 1]))
                index += 2
            }
            channels.append(WaveformOverview(sampleCount: sampleCount, level0: blocks))
            offset += bytes
        }
        return WaveformFileOverview(sampleRate: sampleRate, channels: channels)
    }

    static func saveOverview(_ overview: WaveformFileOverview, forKey key: String) {
        guard !overview.channels.isEmpty, overview.sampleRate > 0 else { return }
        var data = Data()
        var magic: UInt32 = 0x574F_5631
        var channelCount = UInt32(overview.channels.count)
        var sampleRate = Float64(overview.sampleRate)
        var sampleCount = UInt64(overview.channels[0].sampleCount)
        data.append(Data(bytes: &magic, count: 4))
        data.append(Data(bytes: &channelCount, count: 4))
        data.append(Data(bytes: &sampleRate, count: 8))
        data.append(Data(bytes: &sampleCount, count: 8))
        for channel in overview.channels {
            guard let level0 = channel.levels.first else { return }
            var blockCount = UInt32(level0.count)
            data.append(Data(bytes: &blockCount, count: 4))
            var floats: [Float] = []
            floats.reserveCapacity(level0.count * 2)
            for block in level0 {
                floats.append(block.min)
                floats.append(block.max)
            }
            floats.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                data.append(Data(buffer: UnsafeBufferPointer(start: base, count: buffer.count)))
            }
        }
        let url = cacheDirectory.appendingPathComponent(overviewFileName(for: key))
        try? data.write(to: url, options: .atomic)
    }

    private static func fileName(for key: String) -> String {
        "\(digest(for: key)).peaks"
    }

    private static func channelFileName(for key: String) -> String {
        "\(digest(for: key)).channels"
    }

    private static func overviewFileName(for key: String) -> String {
        "\(digest(for: key)).overview"
    }

    private static func readValue<T>(_ data: Data, at offset: Int) -> T {
        let end = offset + MemoryLayout<T>.size
        return data.subdata(in: offset..<end).withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }

    private static func digest(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
