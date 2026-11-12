import Foundation

/// Raw samples around the visible part of each clip, for zoom levels finer than the
/// 32-sample blocks of the overview pyramid. Reads happen off the main actor. Until a window
/// arrives the clip is drawn from the pyramid, so nothing is ever blank.
@MainActor
final class ClipSampleWindowStore {
    /// A read covers at most this many frames per channel.
    static let maximumFrames = 600_000
    /// Visible spans longer than this are drawn from the pyramid alone.
    static let maximumVisibleFrames = 200_000

    struct Window {
        let fileURL: URL
        let origin: Int
        let channels: [[Float]]
        /// Changes with every window stored, so columns built from an older one are rebuilt.
        let generation: Int

        var frameCount: Int { channels.first?.count ?? 0 }

        func covers(_ frames: Range<Int>) -> Bool {
            frames.lowerBound >= origin && frames.upperBound <= origin + frameCount
        }
    }

    private struct Request: Equatable {
        let fileURL: URL
        let frames: Range<Int>
    }

    /// Called on the main actor when a window arrives.
    var onLoad: () -> Void = {}

    private var windows: [UUID: Window] = [:]
    private var requests: [UUID: Request] = [:]
    private var nextGeneration = 1

    /// The window covering `frames` of the clip, starting a read when there is none.
    func window(
        for clipID: UUID,
        fileURL: URL,
        channelCount: Int,
        frames: Range<Int>
    ) -> Window? {
        guard frames.count > 0, frames.count <= Self.maximumVisibleFrames else { return nil }
        if let window = windows[clipID], window.fileURL == fileURL, window.covers(frames) {
            return window
        }
        if let request = requests[clipID], request.fileURL == fileURL,
           request.frames.lowerBound <= frames.lowerBound, request.frames.upperBound >= frames.upperBound {
            return nil
        }
        // Read a visible span either side so a short scroll stays inside the window.
        let pad = min(frames.count, (Self.maximumFrames - frames.count) / 2)
        let read = max(0, frames.lowerBound - pad)..<(frames.upperBound + pad)
        load(Request(fileURL: fileURL, frames: read), for: clipID, channelCount: channelCount)
        return nil
    }

    /// Drops windows for clips no longer shown.
    func retain(_ clipIDs: Set<UUID>) {
        windows = windows.filter { clipIDs.contains($0.key) }
    }

    private func load(_ request: Request, for clipID: UUID, channelCount: Int) {
        requests[clipID] = request
        Task { [weak self] in
            let channels = await Task.detached(priority: .userInitiated) {
                (0..<channelCount).map { channel in
                    WaveformOverviewBuilder.samples(
                        from: request.fileURL,
                        channel: channel,
                        startFrame: request.frames.lowerBound,
                        count: request.frames.count
                    )
                }
            }.value
            self?.store(channels, for: clipID, request: request)
        }
    }

    private func store(_ channels: [[Float]], for clipID: UUID, request: Request) {
        // A newer request for this clip has taken over.
        guard requests[clipID] == request else { return }
        // A failed read keeps its request, so the same span is not read again every frame.
        guard let first = channels.first, !first.isEmpty else { return }
        requests[clipID] = nil
        windows[clipID] = Window(
            fileURL: request.fileURL,
            origin: request.frames.lowerBound,
            channels: channels,
            generation: nextGeneration
        )
        nextGeneration += 1
        onLoad()
    }
}
