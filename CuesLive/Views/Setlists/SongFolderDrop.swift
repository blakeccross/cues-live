import SwiftUI
import UniformTypeIdentifiers

/// Shared Finder-drop parsing for song-folder imports.
enum SongFolderDrop {
    /// Resolves dropped file providers to the URLs of the directories among them.
    static func folderURLs(from providers: [NSItemProvider]) async -> [URL] {
        var folderURLs: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            guard let url = await loadFileURL(from: provider) else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                folderURLs.append(url)
            }
        }
        return folderURLs
    }

    /// Whether any provider carries a file URL, so a drop of plain files can be told apart from a song drag.
    static func containsFileURLs(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    }

    /// Scans each folder off the main actor. Failures come back as display messages, prefixed
    /// with the folder name when more than one folder was dropped.
    static func previews(
        for folderURLs: [URL]
    ) async -> (previews: [SongFolderImporter.Preview], failures: [String]) {
        var previews: [SongFolderImporter.Preview] = []
        var failures: [String] = []
        for url in folderURLs {
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try SongFolderImporter.previewFolder(at: url)
                }.value
                previews.append(preview)
            } catch {
                failures.append(
                    folderURLs.count == 1
                        ? error.localizedDescription
                        : "\(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
        return (previews, failures)
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL:
                    continuation.resume(returning: url)
                case let data as Data:
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Accepts a Finder folder drag on the song library.
struct LiveSetlistSongFolderDropDelegate: DropDelegate {
    let onHover: () -> Void
    let onExit: () -> Void
    let onPerform: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        onHover()
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        onPerform(info.itemProviders(for: [.fileURL]))
    }
}
