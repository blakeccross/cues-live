import Foundation
import SwiftData

enum MediaConsolidator {
    enum ConsolidateError: LocalizedError {
        case missingProjectFile
        case noTracks
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingProjectFile:
                return "This song does not have a project file to consolidate into."
            case .noTracks:
                return "There are no tracks with media to consolidate."
            case .copyFailed(let path):
                return "Could not copy media file at \(path)."
            }
        }
    }

    /// Copies referenced media next to the project file under `Stems/<song name>/` and rewrites paths.
    @discardableResult
    static func consolidate(
        for song: Song,
        context: ModelContext
    ) throws -> URL {
        guard let projectURL = SongProjectBridge.projectURL(for: song) else {
            throw ConsolidateError.missingProjectFile
        }

        let tracks = song.sortedTracks
        guard !tracks.isEmpty else {
            throw ConsolidateError.noTracks
        }

        let stemsDirectory = projectURL
            .deletingLastPathComponent()
            .appendingPathComponent("Stems", isDirectory: true)
            .appendingPathComponent(sanitizedFolderName(song.name), isDirectory: true)
        try FileManager.default.createDirectory(at: stemsDirectory, withIntermediateDirectories: true)

        for track in tracks {
            guard let sourceURL = FileStore.trackURL(for: song, track: track) else { continue }

            let destinationURL = uniqueDestinationURL(
                in: stemsDirectory,
                preferredName: sourceURL.lastPathComponent
            )

            if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }

            var reference = MediaReference.from(url: destinationURL, relativeTo: projectURL)
            MediaReferenceResolver.refreshBookmark(
                for: &reference,
                resolvedURL: destinationURL,
                projectFileURL: projectURL
            )
            track.mediaPath = reference.path
            track.mediaPathStyle = reference.pathStyle
            track.mediaBookmarkData = reference.bookmark
            track.relativeFilePath = destinationURL.lastPathComponent
        }

        try context.save()

        let projectState = try SongProjectBridge.loadProjectState(for: song)
        try SongProjectBridge.persist(
            song: song,
            markers: projectState.markers,
            arrangementSlots: projectState.arrangement.slots,
            clipTrims: projectState.arrangement.clipTrims,
            removedClips: projectState.arrangement.removedClips,
            clipGaps: projectState.arrangement.clipGaps,
            clipRegions: projectState.arrangement.clipRegions,
            loopSlotIDs: projectState.arrangement.loopSlotIDs,
            tempoChanges: projectState.tempoChanges,
            timeSignatureChanges: projectState.timeSignatureChanges,
            midiEvents: projectState.midiEvents,
            context: context
        )
        return stemsDirectory
    }

    private static func sanitizedFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Stems" : trimmed
    }

    private static func uniqueDestinationURL(in directory: URL, preferredName: String) -> URL {
        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(preferredName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let fileName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(fileName)
            index += 1
        }
        return candidate
    }
}
