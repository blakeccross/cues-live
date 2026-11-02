import AVFoundation
import Foundation

/// Loads bundled offline guide WAVs into engine-rate mono stems.
@MainActor
enum SpeechSampleRenderer {
    private static var cache: [String: DecodedStemBuffer] = [:]
    private static var urlByKey: [String: URL]?

    /// Returns a mono float32 buffer at `DecodedStemBuffer.engineSampleRate`, or nil when no sample exists.
    static func renderMonoStem(for text: String) async -> DecodedStemBuffer? {
        monoStem(for: text)
    }

    /// Returns a stereo engine-rate PCM buffer for live announcement playback, or nil when no sample exists.
    static func renderAnnouncementBuffer(for text: String) async -> AVAudioPCMBuffer? {
        guard let stem = monoStem(for: text) else { return nil }
        return stereoPCMBuffer(from: stem)
    }

    static func resetCache() {
        cache.removeAll()
        urlByKey = nil
    }

    // MARK: - Private

    private static func monoStem(for text: String) -> DecodedStemBuffer? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let key = SongSectionNameNormalizer.lookupKey(trimmed)
        if let cached = cache[key] {
            return cached
        }

        guard let url = urlsByNormalizedKey()[key] else { return nil }
        guard let stem = loadMonoStem(from: url) else { return nil }
        cache[key] = stem
        return stem
    }

    private static func loadMonoStem(from url: URL) -> DecodedStemBuffer? {
        do {
            let decoded = try DecodedStemBuffer.decode(from: url)
            if decoded.channelCount == 1 {
                return decoded
            }
            return try downmixToMono(decoded)
        } catch {
            return nil
        }
    }

    private static func urlsByNormalizedKey() -> [String: URL] {
        if let urlByKey {
            return urlByKey
        }

        var lookup: [String: URL] = [:]
        let urls: [URL]
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("SongSections", isDirectory: true),
           let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
           ) {
            urls = contents
        } else {
            urls = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: "SongSections") ?? []
        }

        for url in urls where url.pathExtension.lowercased() == "wav" {
            let name = url.deletingPathExtension().lastPathComponent
            lookup[SongSectionNameNormalizer.lookupKey(name)] = url
        }

        urlByKey = lookup
        return lookup
    }

    private static func downmixToMono(_ buffer: DecodedStemBuffer) throws -> DecodedStemBuffer {
        let frameCount = buffer.frameCount
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.sampleRate,
            channels: 1,
            interleaved: false
        ), let pcm = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let destination = pcm.floatChannelData?[0] else {
            throw DecodedStemBufferError.conversionFailed
        }

        pcm.frameLength = AVAudioFrameCount(frameCount)
        destination.initialize(repeating: 0, count: frameCount)

        let scale = 1 / Float(buffer.channelCount)
        var channelScratch = [Float](repeating: 0, count: frameCount)
        for channel in 0..<buffer.channelCount {
            channelScratch.withUnsafeMutableBufferPointer { scratch in
                guard let base = scratch.baseAddress else { return }
                _ = buffer.copy(
                    channel: channel,
                    startingFrame: 0,
                    frameCount: frameCount,
                    into: base,
                    destinationOffset: 0,
                    gain: scale
                )
                for frame in 0..<frameCount {
                    destination[frame] += base[frame]
                }
            }
        }

        return try DecodedStemBuffer.monoStem(from: pcm, targetSampleRate: buffer.sampleRate)
    }

    private static func stereoPCMBuffer(from stem: DecodedStemBuffer) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: stem.sampleRate,
            channels: 2
        ) else {
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(stem.frameCount)
        ), let channels = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(stem.frameCount)
        let frames = stem.frameCount
        stem.copy(
            channel: 0,
            startingFrame: 0,
            frameCount: frames,
            into: channels[0],
            destinationOffset: 0,
            gain: 1
        )
        stem.copy(
            channel: 0,
            startingFrame: 0,
            frameCount: frames,
            into: channels[1],
            destinationOffset: 0,
            gain: 1
        )
        return buffer
    }
}
