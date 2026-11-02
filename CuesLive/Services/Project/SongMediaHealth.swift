import Foundation
import SwiftData
import UniformTypeIdentifiers

enum SongMediaHealth {
    struct MissingTrack: Identifiable, Hashable {
        var id: UUID { trackID }
        let trackID: UUID
        let songID: UUID
        let songName: String
        let trackName: String
        let expectedFileName: String
    }

    struct RelinkOutcome: Sendable {
        /// Tracks linked in this operation (chosen file + any auto-matched siblings).
        let linkedTrackIDs: [UUID]
        /// How many additional missing tracks were matched by name in the same folder.
        let autoLinkedCount: Int

        var linkedCount: Int { linkedTrackIDs.count }
    }

    enum RelinkError: LocalizedError {
        case trackNotFound
        case missingProjectFile
        case setlistNotFound

        var errorDescription: String? {
            switch self {
            case .trackNotFound:
                return "Could not find that track to relink."
            case .missingProjectFile:
                return "This song does not have a project file."
            case .setlistNotFound:
                return "Could not find that setlist."
            }
        }
    }

    static func missingAudioTracks(in song: Song) -> [AudioTrack] {
        // Touch the relationship so SwiftData faults are filled before filtering.
        let tracks = Array(song.sortedTracks)
        return tracks.filter { FileStore.trackURL(for: song, track: $0) == nil }
    }

    static func hasMissingMedia(_ song: Song) -> Bool {
        !missingAudioTracks(in: song).isEmpty
    }

    static func missingTracks(in song: Song) -> [MissingTrack] {
        missingAudioTracks(in: song).map { track in
            MissingTrack(
                trackID: track.id,
                songID: song.id,
                songName: song.name,
                trackName: track.displayName,
                expectedFileName: expectedFileName(for: track)
            )
        }
    }

    static func missingTracks(in setlist: Setlist) -> [MissingTrack] {
        var seenSongIDs = Set<UUID>()
        var result: [MissingTrack] = []
        // Touch entries so the relationship is faulted in.
        let entries = Array(setlist.sortedEntries)
        for entry in entries {
            guard let song = entry.song, !seenSongIDs.contains(song.id) else { continue }
            seenSongIDs.insert(song.id)
            result.append(contentsOf: missingTracks(in: song))
        }
        return result
    }

    /// Fresh lookup by ID — safe to call from sheets where a passed `@Model` may have empty relationships.
    static func missingTracks(
        forSetlistID setlistID: UUID,
        in context: ModelContext
    ) throws -> [MissingTrack] {
        guard let setlist = try fetchSetlist(id: setlistID, in: context) else {
            throw RelinkError.setlistNotFound
        }
        return missingTracks(in: setlist)
    }

    static func songsWithMissingMedia(in setlist: Setlist) -> [Song] {
        var seen = Set<UUID>()
        var result: [Song] = []
        for entry in setlist.sortedEntries {
            guard let song = entry.song, !seen.contains(song.id) else { continue }
            seen.insert(song.id)
            if hasMissingMedia(song) {
                result.append(song)
            }
        }
        return result
    }

    static func fetchSetlist(id: UUID, in context: ModelContext) throws -> Setlist? {
        var descriptor = FetchDescriptor<Setlist>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func fetchSong(id: UUID, in context: ModelContext) throws -> Song? {
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Relinks one track, then tries to auto-link other missing tracks in the same song
    /// by matching expected filenames in the chosen file's folder.
    @discardableResult
    static func relink(
        trackID: UUID,
        in song: Song,
        to fileURL: URL,
        context: ModelContext
    ) throws -> RelinkOutcome {
        guard let track = song.tracks.first(where: { $0.id == trackID }) else {
            throw RelinkError.trackNotFound
        }

        let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: context)
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        applyMediaLink(to: track, fileURL: fileURL, projectURL: projectURL)

        let directory = fileURL.deletingLastPathComponent()
        let directoryAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if directoryAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        let autoLinkedIDs = try autoLinkMissingTracks(
            in: song,
            directory: directory,
            excludingTrackID: trackID,
            projectURL: projectURL
        )

        try context.save()
        try SongProjectBridge.syncProjectFile(for: song, context: context)

        return RelinkOutcome(
            linkedTrackIDs: [trackID] + autoLinkedIDs,
            autoLinkedCount: autoLinkedIDs.count
        )
    }

    // MARK: - Private

    private static func applyMediaLink(
        to track: AudioTrack,
        fileURL: URL,
        projectURL: URL
    ) {
        var reference = MediaReference.from(url: fileURL, relativeTo: projectURL)
        MediaReferenceResolver.refreshBookmark(
            for: &reference,
            resolvedURL: fileURL,
            projectFileURL: projectURL
        )
        track.mediaPath = reference.path
        track.mediaPathStyle = reference.pathStyle
        track.mediaBookmarkData = reference.bookmark
        track.relativeFilePath = fileURL.lastPathComponent
    }

    private static func autoLinkMissingTracks(
        in song: Song,
        directory: URL,
        excludingTrackID: UUID,
        projectURL: URL
    ) throws -> [UUID] {
        let stillMissing = missingAudioTracks(in: song).filter { $0.id != excludingTrackID }
        guard !stillMissing.isEmpty else { return [] }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && isSupportedAudioFile(url)
        }

        let lookup = filenameLookup(for: fileURLs)
        var linkedIDs: [UUID] = []
        var claimedURLs = Set<URL>()

        for track in stillMissing {
            guard let matchURL = matchingFileURL(
                for: track,
                in: lookup,
                excluding: claimedURLs
            ) else {
                continue
            }

            applyMediaLink(to: track, fileURL: matchURL, projectURL: projectURL)
            claimedURLs.insert(matchURL.standardizedFileURL)
            linkedIDs.append(track.id)
        }

        return linkedIDs
    }

    private static func filenameLookup(for fileURLs: [URL]) -> [String: URL] {
        var lookup: [String: URL] = [:]
        for url in fileURLs {
            let filename = url.lastPathComponent.lowercased()
            lookup[filename] = url

            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            if lookup[base] == nil {
                lookup[base] = url
            }
        }
        return lookup
    }

    private static func matchingFileURL(
        for track: AudioTrack,
        in lookup: [String: URL],
        excluding claimedURLs: Set<URL>
    ) -> URL? {
        for candidate in candidateNames(for: track) {
            let key = candidate.lowercased()
            guard let url = lookup[key],
                  !claimedURLs.contains(url.standardizedFileURL) else {
                continue
            }
            return url
        }
        return nil
    }

    private static func candidateNames(for track: AudioTrack) -> [String] {
        var names: [String] = []
        let expected = expectedFileName(for: track)
        if !expected.isEmpty {
            names.append(expected)
            names.append((expected as NSString).deletingPathExtension)
        }

        let display = track.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty {
            names.append(display)
            names.append((display as NSString).deletingPathExtension)
            for ext in ["wav", "aiff", "aif", "mp3", "m4a", "caf"] {
                names.append("\(display).\(ext)")
            }
        }

        var seen = Set<String>()
        return names.filter { name in
            let key = name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func isSupportedAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext) else {
            return false
        }
        return FileStore.supportedTypes.contains { type.conforms(to: $0) }
            || ["wav", "aiff", "aif", "mp3", "m4a", "caf"].contains(ext)
    }

    private static func expectedFileName(for track: AudioTrack) -> String {
        if !track.relativeFilePath.isEmpty {
            return track.relativeFilePath
        }
        if let mediaPath = track.mediaPath, !mediaPath.isEmpty {
            return URL(fileURLWithPath: mediaPath).lastPathComponent
        }
        return track.displayName
    }
}
