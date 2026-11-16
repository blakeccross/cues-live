import AVFoundation
import CoreGraphics
import Foundation
import Observation

/// Frames of a movie for the video lane, decoded off the main thread and kept by movie time.
@MainActor
@Observable
final class VideoThumbnailStore {
    /// Decoded frames keyed by `key(forSeconds:)`.
    private(set) var images: [Int: CGImage] = [:]

    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var pixelHeight = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Frames are requested on a 0.1 s grid so small zoom changes reuse what is cached.
    static let timeGrid: TimeInterval = 0.1
    /// Most frames kept before the cache is cleared and refilled for the current zoom.
    private static let maximumCachedImages = 600
    /// A nearby keyframe is close enough for a thumbnail and decodes much faster.
    private static let timeTolerance = CMTime(seconds: 0.25, preferredTimescale: 600)

    static func key(forSeconds seconds: TimeInterval) -> Int {
        Int((seconds / timeGrid).rounded())
    }

    static func gridSeconds(_ seconds: TimeInterval) -> TimeInterval {
        Double(key(forSeconds: seconds)) * timeGrid
    }

    func image(atSeconds seconds: TimeInterval) -> CGImage? {
        images[Self.key(forSeconds: seconds)]
    }

    /// Decodes the frames at `times` that are not cached yet, replacing any earlier request.
    func load(url: URL?, times: [TimeInterval], pixelHeight: Int) {
        if url != self.url || pixelHeight != self.pixelHeight {
            task?.cancel()
            images = [:]
            self.url = url
            self.pixelHeight = pixelHeight
        }
        guard let url, pixelHeight > 0 else { return }
        if images.count > Self.maximumCachedImages {
            images = [:]
        }
        var seen = Set<Int>()
        let missing = times.map(Self.key(forSeconds:)).filter { images[$0] == nil && seen.insert($0).inserted }
        guard !missing.isEmpty else { return }

        task?.cancel()
        task = Task { [weak self] in
            await self?.decode(keys: missing, from: url, pixelHeight: pixelHeight)
        }
    }

    private func decode(keys: [Int], from url: URL, pixelHeight: Int) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 0, height: CGFloat(pixelHeight))
        generator.requestedTimeToleranceBefore = Self.timeTolerance
        generator.requestedTimeToleranceAfter = Self.timeTolerance
        let times = keys.map { CMTime(seconds: Double($0) * Self.timeGrid, preferredTimescale: 600) }
        for await result in generator.images(for: times) {
            guard !Task.isCancelled, url == self.url else { return }
            guard let image = try? result.image else { continue }
            images[Self.key(forSeconds: result.requestedTime.seconds)] = image
        }
    }
}
