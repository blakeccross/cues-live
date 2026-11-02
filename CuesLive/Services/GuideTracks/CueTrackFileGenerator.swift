import Foundation
import SwiftData

enum CueTrackFileGeneratorError: LocalizedError {
    case missingProjectFile
    case invalidDuration
    case noSections
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProjectFile:
            return "This song does not have a project file."
        case .invalidDuration:
            return "Add tracks or arrangement length before generating cues."
        case .noSections:
            return "Add section markers before generating cues."
        case .generationFailed(let message):
            return message
        }
    }
}

enum CueTrackFileGenerator {
    static let trackDisplayName = "Cues"
    static let fileName = "Cues.caf"

    static func existingCueTrack(in song: Song) -> AudioTrack? {
        song.sortedTracks.first {
            $0.displayName.caseInsensitiveCompare(trackDisplayName) == .orderedSame
        }
    }

    static func hasCueTrack(in song: Song) -> Bool {
        existingCueTrack(in: song) != nil
    }

    static func timelineDuration(
        for song: Song,
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> TimeInterval {
        SongTrackLoader.timelineDuration(for: song, sourceDurationForTrack: sourceDurationForTrack)
    }

    static func rulerSections(
        for song: Song,
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> [ArrangementDisplaySection] {
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        let markers = projectState.markers
        let arrangement = projectState.arrangement
        let inputs = SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: song.sortedTracks.map(\.id),
            sourceDurationForTrack: sourceDurationForTrack
        )
        let layout = SongArrangementStore.buildLayoutSnapshot(
            slots: arrangement.slots,
            clipTrims: arrangement.clipTrims,
            removedClips: arrangement.removedClips,
            clipGaps: arrangement.clipGaps,
            clipRegions: arrangement.clipRegions,
            inputs: inputs
        )
        return layout.rulerSections
    }

    static func scheduledAnnouncements(
        for song: Song,
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> [CueAnnouncement] {
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        let sections = rulerSections(for: song, sourceDurationForTrack: sourceDurationForTrack)
        return CueTrackScheduler.scheduledAnnouncements(
            sections: sections.map { ($0.name, $0.timelineStartSeconds) },
            tempoChanges: projectState.tempoChanges,
            timeSignatureChanges: projectState.timeSignatureChanges
        )
    }

    /// Generates a spoken-cues audio file for the song timeline and links or replaces a Cues track.
    @MainActor
    @discardableResult
    static func generateAndAttach(
        to song: Song,
        context: ModelContext,
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) async throws -> AudioTrack {
        let duration = timelineDuration(for: song, sourceDurationForTrack: sourceDurationForTrack)
        guard duration > 0 else {
            throw CueTrackFileGeneratorError.invalidDuration
        }

        let announcements = scheduledAnnouncements(
            for: song,
            sourceDurationForTrack: sourceDurationForTrack
        )
        guard !announcements.isEmpty else {
            throw CueTrackFileGeneratorError.noSections
        }

        let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: context)

        var speechBuffers: [String: DecodedStemBuffer] = [:]
        for name in Set(announcements.map(\.name)) {
            guard let buffer = await SpeechSampleRenderer.renderMonoStem(for: name) else {
                throw CueTrackFileGeneratorError.generationFailed("Could not speak “\(name)”.")
            }
            speechBuffers[name] = buffer
        }

        let buffer: DecodedStemBuffer
        do {
            buffer = try CueTrackGenerator.generate(
                duration: duration,
                announcements: announcements,
                speechBuffers: speechBuffers
            )
        } catch {
            throw CueTrackFileGeneratorError.generationFailed(error.localizedDescription)
        }

        let outputURL = try cueFileURL(for: song, projectFileURL: projectURL)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try StemAudioWriter.writeCAF(buffer: buffer, to: outputURL)

        let track: AudioTrack
        if let existing = existingCueTrack(in: song) {
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
                throw CueTrackFileGeneratorError.generationFailed("Could not link cues track.")
            }
            created.displayName = trackDisplayName
            created.trimEndSeconds = duration
            context.insert(created)
            song.tracks.append(created)
            track = created
        }

        // Prefer the baked cues stem over live TTS so callouts are not doubled.
        song.dynamicCuesEnabled = false

        TrackGroupStore.ensureDefaults(in: context)
        track.group = TrackGroupStore.findOrCreateGroup(named: "Cues", in: context)
        TrackGroupStore.reorderTracksByGroup(in: song, context: context)

        try context.save()
        try SongProjectBridge.syncProjectFile(for: song, context: context)
        return track
    }

    private static func cueFileURL(for song: Song, projectFileURL: URL) throws -> URL {
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
