import Foundation

/// Resolved file URLs of media references, so a view can look a track's file up on every update.
///
/// Resolving a security-scoped bookmark is a round trip to the system's bookmark agent and a
/// code-signature check. The editor resolves each track's file whenever it lays out the lanes,
/// so without this a vertical scroll spent about a quarter of each frame resolving bookmarks.
/// A reference that changes is a new key, and a cached file that no longer exists is resolved
/// again, so a relink or a moved file still shows up.
@MainActor
final class TrackURLCache {
    static let shared = TrackURLCache()

    private struct Key: Hashable {
        let reference: MediaReference
        let projectFileURL: URL?
    }

    private let resolve: (MediaReference, URL?) -> URL?
    private let fileExists: (URL) -> Bool
    private var urls: [Key: URL] = [:]

    init(
        resolve: @escaping (MediaReference, URL?) -> URL? = MediaReferenceResolver.resolve(_:projectFileURL:),
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.resolve = resolve
        self.fileExists = fileExists
    }

    /// The file `reference` points to, resolved once while it keeps existing. Nil results are
    /// not kept, so a file that appears later is found.
    func url(for reference: MediaReference, projectFileURL: URL?) -> URL? {
        let key = Key(reference: reference, projectFileURL: projectFileURL)
        if let cached = urls[key] {
            if fileExists(cached) { return cached }
            urls[key] = nil
        }
        guard let url = resolve(reference, projectFileURL) else { return nil }
        urls[key] = url
        return url
    }
}
