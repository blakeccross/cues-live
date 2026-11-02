import Foundation
import SwiftData

enum ClickTrackFileGeneratorError: LocalizedError {
    case missingProjectFile
    case invalidDuration
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProjectFile:
            return "This song does not have a project file."
        case .invalidDuration:
            return "Add tracks or arrangement length before generating a click."
        case .generationFailed(let message):
            return message
        }
    }
}

enum ClickTrackFileGenerator {
    static let trackDisplayName = "Click"
    static let fileName = "Click.caf"

    static func existingClickTrack(in song: Song) -> AudioTrack? {
        song.sortedTracks.first {
            $0.displayName.caseInsensitiveCompare(trackDisplayName) == .orderedSame
        }
    }

    static func hasClickTrack(in song: Song) -> Bool {
        existingClickTrack(in: song) != nil
    }

    static func timelineDuration(
        for song: Song,
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> TimeInterval {
        SongTrackLoader.timelineDuration(for: song, sourceDurationForTrack: sourceDurationForTrack)
    }

    /// Generates a click audio file for the song timeline and links or replaces a Click track.
    @discardableResult
    static func generateAndAttach(
        to song: Song,
        context: ModelContext,
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) throws -> AudioTrack {
        let duration = timelineDuration(for: song, sourceDurationForTrack: sourceDurationForTrack)
        guard duration > 0 else {
            throw ClickTrackFileGeneratorError.invalidDuration
        }

        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        return try generateAndAttach(
            to: song,
            context: context,
            duration: duration,
            tempoChanges: projectState.tempoChanges,
            timeSignatureChanges: projectState.timeSignatureChanges
        )
    }

    /// Generates a click audio file for an explicit duration and links or replaces a Click track.
    @discardableResult
    static func generateAndAttach(
        to song: Song,
        context: ModelContext,
        duration: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) throws -> AudioTrack {
        guard duration > 0 else {
            throw ClickTrackFileGeneratorError.invalidDuration
        }

        let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: context)

        let buffer: DecodedStemBuffer
        do {
            buffer = try ClickTrackGenerator.generate(
                duration: duration,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                subdivision: .quarter
            )
        } catch {
            throw ClickTrackFileGeneratorError.generationFailed(error.localizedDescription)
        }

        let outputURL = try clickFileURL(for: song, projectFileURL: projectURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try StemAudioWriter.writeCAF(buffer: buffer, to: outputURL)

        let track: AudioTrack
        if let existing = existingClickTrack(in: song) {
            var reference = MediaReference.from(url: outputURL, relativeTo: projectURL)
            MediaReferenceResolver.refreshBookmark(
                for: &reference,
                resolvedURL: outputURL,
                projectFileURL: projectURL
            )
            existing.displayName = trackDisplayName
            existing.relativeFilePath = outputURL.lastPathComponent
            existing.mediaPath = reference.path
            existing.mediaPathStyle = reference.pathStyle
            existing.mediaBookmarkData = reference.bookmark
            existing.trimStartSeconds = 0
            existing.trimEndSeconds = duration
            track = existing
        } else {
            let linked = try FileStore.linkTracks(
                from: [outputURL],
                into: song,
                projectFileURL: projectURL
            )
            guard let created = linked.first else {
                throw ClickTrackFileGeneratorError.generationFailed("Could not link click track.")
            }
            created.displayName = trackDisplayName
            created.trimEndSeconds = duration
            context.insert(created)
            song.tracks.append(created)
            track = created
        }

        TrackGroupStore.ensureDefaults(in: context)
        track.group = TrackGroupStore.findOrCreateGroup(named: "Click", in: context)
        TrackGroupStore.reorderTracksByGroup(in: song, context: context)

        try context.save()
        try SongProjectBridge.syncProjectFile(for: song, context: context)
        return track
    }

    private static func clickFileURL(for song: Song, projectFileURL: URL) throws -> URL {
        let stemsDirectory = projectFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Stems", isDirectory: true)
            .appendingPathComponent(sanitizedFolderName(song.name), isDirectory: true)
        try FileManager.default.createDirectory(at: stemsDirectory, withIntermediateDirectories: true)
        return stemsDirectory.appendingPathComponent(fileName)
    }

    private static func sanitizedFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Stems" : trimmed
    }
}
