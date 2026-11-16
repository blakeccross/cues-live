import AVFoundation
import Foundation
import UniformTypeIdentifiers

extension FileStore {
    static let supportedVideoTypes: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie]

    /// A Finder item this editor can attach as the song's video.
    static func isSupportedVideoFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return false
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedVideoTypes.contains { type.conforms(to: $0) }
    }

    static func videoURL(for song: Song) -> URL? {
        guard let reference = song.videoTrack?.mediaReference else { return nil }
        return MediaReferenceResolver.resolve(
            reference,
            projectFileURL: SongProjectBridge.projectURL(for: song)
        )
    }

    /// The movie's length and picture size, or nil when it has no readable video track.
    static func videoInfo(at url: URL) async -> VideoFileInfo? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let duration = try? await asset.load(.duration) else {
            return nil
        }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        let size = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let oriented = size.applying(transform)
        return VideoFileInfo(
            durationSeconds: seconds,
            pixelSize: CGSize(width: abs(oriented.width), height: abs(oriented.height))
        )
    }
}

struct VideoFileInfo: Equatable, Sendable {
    let durationSeconds: TimeInterval
    let pixelSize: CGSize

    /// Width over height, 16:9 when the size is unknown.
    var aspectRatio: CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return 16.0 / 9.0 }
        return pixelSize.width / pixelSize.height
    }
}
