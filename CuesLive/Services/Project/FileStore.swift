import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum FileStore {
    static let supportedTypes: [UTType] = [.wav, .aiff, .audio, .mp3, .mpeg4Audio]

    /// A Finder item this editor can place as a track. Folders and other documents are not audio.
    static func isSupportedAudioFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return false
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func isInAppContainer(_ url: URL) -> Bool {
        let containerRoot = documentsDirectory.standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(containerRoot)
    }

    static func trackURL(for song: Song, track: AudioTrack) -> URL? {
        guard let mediaPath = track.mediaPath, let pathStyle = track.mediaPathStyle else {
            return nil
        }
        let reference = MediaReference(
            path: mediaPath,
            pathStyle: pathStyle,
            bookmark: track.mediaBookmarkData
        )
        return MediaReferenceResolver.resolve(
            reference,
            projectFileURL: SongProjectBridge.projectURL(for: song)
        )
    }

    @discardableResult
    static func linkTracks(
        from sourceURLs: [URL],
        into song: Song,
        projectFileURL: URL
    ) throws -> [AudioTrack] {
        var linkedTracks: [AudioTrack] = []
        let existingCount = song.tracks.count

        for (index, sourceURL) in sourceURLs.enumerated() {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let fileName = sourceURL.lastPathComponent
            let fileExtension = sourceURL.pathExtension
            let displayName = fileName
                .replacingOccurrences(of: ".\(fileExtension)", with: "", options: .caseInsensitive)

            let reference = MediaReference.from(url: sourceURL, relativeTo: projectFileURL)
            let track = AudioTrack(
                displayName: displayName.isEmpty ? fileName : displayName,
                relativeFilePath: fileName,
                sortOrder: existingCount + index
            )
            track.mediaPath = reference.path
            track.mediaPathStyle = reference.pathStyle
            track.mediaBookmarkData = reference.bookmark
            track.song = song
            linkedTracks.append(track)
        }

        return linkedTracks
    }

    static func deleteProjectFile(for song: Song) {
        guard let path = song.projectFilePath else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    /// Source length of a track's audio. Refreshes the cached length while the file is readable
    /// and falls back to it when the file is missing, so the timeline keeps its size.
    static func sourceDuration(for song: Song, track: AudioTrack) -> TimeInterval? {
        if let url = trackURL(for: song, track: track), let duration = fileDuration(at: url) {
            cacheSourceDuration(duration, for: track)
            return duration
        }
        return track.sourceDurationSeconds
    }

    static func cacheSourceDuration(_ duration: TimeInterval, for track: AudioTrack) {
        if track.sourceDurationSeconds.map({ abs($0 - duration) > 0.001 }) ?? true {
            track.sourceDurationSeconds = duration
        }
    }

    static func fileDuration(at url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
