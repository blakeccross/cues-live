import Foundation
import SwiftData

enum SongFolderImporter {
    struct ScanResult {
        let suggestedName: String
        let abletonURL: URL?
        let trackURLs: [URL]
    }

    struct ImportResult {
        let song: Song
        let trackCount: Int
        let sectionCount: Int
        let bpm: Double?
    }

    static func summaryMessage(for result: ImportResult) -> String {
        var lines = [
            "Created \"\(result.song.name)\" with \(result.trackCount) track\(result.trackCount == 1 ? "" : "s")."
        ]
        if let bpm = result.bpm {
            if result.sectionCount > 0 {
                var line = "Imported \(result.sectionCount) sections from Ableton at \(String(format: "%.1f", bpm)) BPM."
                if let timeSignature = result.song.timeSignatureDisplay {
                    line += " Time signature: \(timeSignature)."
                }
                lines.append(line)
            } else {
                var line = "Imported Ableton tempo at \(String(format: "%.1f", bpm)) BPM."
                if let timeSignature = result.song.timeSignatureDisplay {
                    line += " Time signature: \(timeSignature)."
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    enum ImportError: LocalizedError {
        case unreadableFolder
        case noImportableContent

        var errorDescription: String? {
            switch self {
            case .unreadableFolder:
                return "Could not read the selected folder."
            case .noImportableContent:
                return "No multitrack audio files were found in the folder. Add a Multitracks or Stems subfolder with audio files."
            }
        }
    }

    private static let preferredStemFolderNames = [
        "multitracks", "multitrack", "stems", "tracks", "audio"
    ]

    private static let supportedExtensions: Set<String> = ["wav", "aiff", "aif", "mp3", "m4a", "caf"]

    static func scanFolder(at folderURL: URL) throws -> ScanResult {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        return try scanFolderContents(at: folderURL)
    }

    static func importFromFolder(
        at folderURL: URL,
        name: String? = nil,
        context: ModelContext
    ) throws -> ImportResult {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let scan = try scanFolderContents(at: folderURL)

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let songName = trimmedName.isEmpty ? scan.suggestedName : trimmedName

        let song = Song(name: songName)
        context.insert(song)

        let projectURL = ProjectFileStore.defaultProjectURL(for: songName)
        song.projectFilePath = projectURL.path

        do {
            let result = try applyScanResult(
                scan,
                to: song,
                context: context,
                projectURL: projectURL
            )
            try SongProjectBridge.syncProjectFile(for: song, context: context)
            try context.save()
            return ImportResult(
                song: song,
                trackCount: result.trackCount,
                sectionCount: result.sectionCount,
                bpm: result.bpm
            )
        } catch {
            context.delete(song)
            if let path = song.projectFilePath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
            throw error
        }
    }

    static func importIntoExistingSong(
        at folderURL: URL,
        song: Song,
        context: ModelContext
    ) throws -> (trackCount: Int, sectionCount: Int, bpm: Double?) {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let scan = try scanFolderContents(at: folderURL)
        let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: context)
        let result = try applyScanResult(
            scan,
            to: song,
            context: context,
            projectURL: projectURL
        )
        try SongProjectBridge.syncProjectFile(for: song, context: context)
        try context.save()
        return (result.trackCount, result.sectionCount, result.bpm)
    }

    private static func scanFolderContents(at folderURL: URL) throws -> ScanResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ImportError.unreadableFolder
        }

        let suggestedName = folderURL.lastPathComponent
        let abletonURL = findAbletonFile(in: folderURL, folderName: suggestedName)
        let trackURLs = findTrackFiles(in: folderURL)

        guard abletonURL != nil || !trackURLs.isEmpty else {
            throw ImportError.noImportableContent
        }

        return ScanResult(
            suggestedName: suggestedName,
            abletonURL: abletonURL,
            trackURLs: trackURLs
        )
    }

    private struct AppliedScanResult {
        let trackCount: Int
        let sectionCount: Int
        let bpm: Double?
    }

    private static func applyScanResult(
        _ scan: ScanResult,
        to song: Song,
        context: ModelContext,
        projectURL: URL
    ) throws -> AppliedScanResult {
        var trackCount = 0
        var sectionCount = 0
        var bpm: Double?

        if !scan.trackURLs.isEmpty {
            let tracks = try FileStore.linkTracks(
                from: scan.trackURLs,
                into: song,
                projectFileURL: projectURL
            )
            for track in tracks {
                context.insert(track)
                song.tracks.append(track)
            }
            trackCount = tracks.count
            TrackGroupStore.autoAssignGroups(for: song, in: context)
        }

        if let abletonURL = scan.abletonURL {
            let importResult = try AbletonProjectImporter.importFrom(url: abletonURL)
            let markers = AbletonProjectImporter.makeMarkers(from: importResult).sortedByTime
            try AbletonProjectImporter.apply(
                importResult,
                markers: markers,
                to: song,
                context: context
            )
            if markers.isEmpty {
                try SongProjectBridge.syncProjectFile(
                    for: song,
                    context: context,
                    tempoChanges: [TempoChange(startMeasure: 1, bpm: importResult.bpm, sortOrder: 0)],
                    timeSignatureChanges: importResult.timeSignatures
                )
            } else {
                let slots = SongArrangementStore.defaultSlots(from: markers)
                let arrangement = SongArrangement(
                    slots: slots,
                    clipTrims: [],
                    removedClips: [],
                    clipGaps: [],
                    clipRegions: []
                )
                try SongProjectBridge.syncProjectFile(
                    for: song,
                    context: context,
                    markers: markers,
                    arrangement: arrangement,
                    tempoChanges: [TempoChange(startMeasure: 1, bpm: importResult.bpm, sortOrder: 0)],
                    timeSignatureChanges: importResult.timeSignatures
                )
            }
            sectionCount = importResult.sections.count
            bpm = importResult.bpm
        }

        guard trackCount > 0 else {
            throw ImportError.noImportableContent
        }

        return AppliedScanResult(
            trackCount: trackCount,
            sectionCount: sectionCount,
            bpm: bpm
        )
    }

    private static func findAbletonFile(in folderURL: URL, folderName: String) -> URL? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let alsFiles = children.filter { $0.pathExtension.lowercased() == "als" }

        if alsFiles.count == 1 {
            return alsFiles[0]
        }

        if let matching = alsFiles.first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased() == folderName.lowercased()
        }) {
            return matching
        }

        return alsFiles.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }.first
    }

    private static func findTrackFiles(in folderURL: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var directories: [(url: URL, name: String)] = []
        var rootAudio: [URL] = []

        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey]) else { continue }
            if values.isDirectory == true {
                directories.append((child, child.lastPathComponent.lowercased()))
            } else if isSupportedAudioFile(child) {
                rootAudio.append(child)
            }
        }

        for preferredName in preferredStemFolderNames {
            if let match = directories.first(where: { $0.name == preferredName }) {
                let tracks = audioFiles(in: match.url)
                if !tracks.isEmpty {
                    return tracks
                }
            }
        }

        let directoriesWithAudio = directories.compactMap { directory -> (URL, Int)? in
            let tracks = audioFiles(in: directory.url)
            return tracks.isEmpty ? nil : (directory.url, tracks.count)
        }

        if let best = directoriesWithAudio.max(by: { $0.1 < $1.1 }) {
            return audioFiles(in: best.0)
        }

        return rootAudio.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func audioFiles(in directory: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter(isSupportedAudioFile)
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    private static func isSupportedAudioFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
