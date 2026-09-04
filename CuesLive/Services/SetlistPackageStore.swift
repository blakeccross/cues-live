import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum SetlistPackageStore {
    static let showFileName = "show.\(ProjectUTType.showProjectExtension)"
    static let songsFolderName = "Songs"

    enum PackageError: LocalizedError {
        case missingShowFile
        case missingProjectFile(String)
        case copyFailed(String)
        case invalidPackage

        var errorDescription: String? {
            switch self {
            case .missingShowFile:
                return "This setlist package is missing its show file."
            case .missingProjectFile(let name):
                return "Could not find a project file for “\(name)”."
            case .copyFailed(let path):
                return "Could not copy media file at \(path)."
            case .invalidPackage:
                return "This does not look like a cues.live setlist package."
            }
        }
    }

    static var packagesDirectory: URL {
        let directory = FileStore.documentsDirectory
            .appendingPathComponent("cues.live", isDirectory: true)
            .appendingPathComponent("SetlistPackages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Collects songs, stems, clicks, headers, and transitions into a plain folder:
    /// `<Setlist Name>/show.cueshow` + `Songs/<Song>/…`
    /// Does not mutate the live library's media paths.
    static func export(
        setlist: Setlist,
        to destinationURL: URL,
        context: ModelContext
    ) throws {
        for entry in setlist.sortedEntries {
            guard let song = entry.song else { continue }
            try SongProjectBridge.ensureProjectFile(for: song, context: context)
            try SongProjectBridge.syncProjectFile(for: song, context: context)
        }

        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MTLSetlistExport-\(UUID().uuidString)", isDirectory: true)
        let folderName = sanitizedExportFolderName(from: destinationURL)
        let stagingPackage = stagingRoot.appendingPathComponent(folderName, isDirectory: true)

        try fileManager.createDirectory(at: stagingPackage, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let songsDirectory = stagingPackage.appendingPathComponent(songsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: songsDirectory, withIntermediateDirectories: true)

        var packagedSongURLs: [UUID: URL] = [:]
        var seenSongIDs = Set<UUID>()
        var usedSongFolderNames = Set<String>()

        for entry in setlist.sortedEntries {
            guard let song = entry.song, !seenSongIDs.contains(song.id) else { continue }
            seenSongIDs.insert(song.id)

            let songFolderName = uniqueSongFolderName(
                for: song.name,
                usedNames: &usedSongFolderNames
            )
            let songFolderURL = songsDirectory.appendingPathComponent(songFolderName, isDirectory: true)
            try fileManager.createDirectory(at: songFolderURL, withIntermediateDirectories: true)

            let packagedProjectURL = songFolderURL.appendingPathComponent(
                "\(songFolderName).\(ProjectUTType.songProjectExtension)"
            )
            try packageSong(song, into: songFolderURL, projectURL: packagedProjectURL)
            packagedSongURLs[song.id] = packagedProjectURL
        }

        let showURL = stagingPackage.appendingPathComponent(showFileName)
        let document = buildPackagedShowDocument(
            from: setlist,
            showFileURL: showURL,
            packagedSongURLs: packagedSongURLs
        )
        try ShowFileStore.save(document, to: showURL)

        let finalDestination = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)

        if fileManager.fileExists(atPath: finalDestination.path) {
            try fileManager.removeItem(at: finalDestination)
        }
        try fileManager.createDirectory(
            at: finalDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: stagingPackage, to: finalDestination)
    }

    /// Installs a package into the app documents tree and imports it into SwiftData.
    @discardableResult
    static func importPackage(
        from url: URL,
        into context: ModelContext
    ) throws -> Setlist {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let packageURL = try resolvePackageRoot(from: url)
        let installedURL = try installIntoDocuments(packageURL)
        let showURL = installedURL.appendingPathComponent(showFileName)
        guard FileManager.default.fileExists(atPath: showURL.path) else {
            throw PackageError.missingShowFile
        }

        let document = try ShowFileStore.load(from: showURL)
        if let existing = try findSetlist(id: document.id, in: context) {
            for entry in existing.entries {
                context.delete(entry)
            }
            existing.entries.removeAll()
            context.delete(existing)
            try context.save()
        }

        return try SongProjectBridge.importShow(from: showURL, into: context)
    }

    static func resolvePackageRoot(from url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue {
            let showURL = url.appendingPathComponent(showFileName)
            if FileManager.default.fileExists(atPath: showURL.path) {
                return url
            }
            throw PackageError.invalidPackage
        }

        if url.lastPathComponent == showFileName
            || url.pathExtension == ProjectUTType.showProjectExtension {
            let parent = url.deletingLastPathComponent()
            let siblingShow = parent.appendingPathComponent(showFileName)
            if FileManager.default.fileExists(atPath: siblingShow.path)
                || FileManager.default.fileExists(atPath: url.path) {
                return parent
            }
        }

        throw PackageError.invalidPackage
    }

    // MARK: - Private

    private static func installIntoDocuments(_ packageURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let destination = uniquePackageDestination(for: packageURL.lastPathComponent)

        if destination.standardizedFileURL == packageURL.standardizedFileURL {
            return destination
        }

        if FileStore.isInAppContainer(packageURL),
           packageURL.path.hasPrefix(packagesDirectory.path) {
            return packageURL
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: packageURL, to: destination)
        return destination
    }

    private static func uniquePackageDestination(for fileName: String) -> URL {
        let baseName = sanitizedExportFolderName(from: URL(fileURLWithPath: fileName))

        var candidate = packagesDirectory.appendingPathComponent(baseName, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = packagesDirectory.appendingPathComponent(
                "\(baseName) \(index)",
                isDirectory: true
            )
            index += 1
        }
        return candidate
    }

    /// Layout per song:
    /// ```
    /// Songs/<Song Name>/
    ///   <Song Name>.cueslive
    ///   Stems/
    ///     kick.wav
    ///     ...
    /// ```
    private static func packageSong(
        _ song: Song,
        into songFolderURL: URL,
        projectURL packagedProjectURL: URL
    ) throws {
        guard let sourceProjectURL = SongProjectBridge.projectURL(for: song) else {
            throw PackageError.missingProjectFile(song.name)
        }

        var document = try ProjectFileStore.load(from: sourceProjectURL)
        document.bakeManifest = nil

        let stemsDirectory = songFolderURL.appendingPathComponent("Stems", isDirectory: true)

        var updatedTracks: [ProjectTrack] = []
        for track in document.tracks {
            let sourceURL = MediaReferenceResolver.resolve(
                track.media,
                projectFileURL: sourceProjectURL
            ) ?? song.sortedTracks
                .first(where: { $0.id == track.id })
                .flatMap { FileStore.trackURL(for: song, track: $0) }

            guard let sourceURL else {
                updatedTracks.append(track)
                continue
            }

            try FileManager.default.createDirectory(at: stemsDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(
                in: stemsDirectory,
                preferredName: sourceURL.lastPathComponent
            )

            do {
                if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                throw PackageError.copyFailed(sourceURL.path)
            }

            var media = MediaReference.from(url: destinationURL, relativeTo: packagedProjectURL)
            MediaReferenceResolver.refreshBookmark(
                for: &media,
                resolvedURL: destinationURL,
                projectFileURL: packagedProjectURL
            )

            var updatedTrack = track
            updatedTrack.media = media
            updatedTracks.append(updatedTrack)
        }

        document.tracks = updatedTracks
        try ProjectFileStore.save(document, to: packagedProjectURL)
    }

    private static func uniqueSongFolderName(
        for songName: String,
        usedNames: inout Set<String>
    ) -> String {
        let base = sanitizedFolderName(songName)
        var candidate = base
        var index = 2
        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(base) \(index)"
            index += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }

    private static func buildPackagedShowDocument(
        from setlist: Setlist,
        showFileURL: URL,
        packagedSongURLs: [UUID: URL]
    ) -> ShowProjectDocument {
        let entries = setlist.sortedEntries.compactMap { entry -> ShowProjectEntry? in
            if entry.isHeader, let headerTitle = entry.headerTitle {
                return ShowProjectEntry(
                    sortOrder: entry.sortOrder,
                    headerTitle: headerTitle,
                    headerTimeSeconds: entry.headerTimeSeconds
                )
            }

            guard let song = entry.song,
                  let projectURL = packagedSongURLs[song.id] else {
                return nil
            }

            return ShowProjectEntry(
                sortOrder: entry.sortOrder,
                transition: entry.transition,
                songProject: ProjectDocumentReference.from(
                    projectURL: projectURL,
                    relativeTo: showFileURL
                ),
                overlap: entry.transition == .overlap ? entry.overlapConfig : nil
            )
        }

        return ShowProjectDocument(
            id: setlist.id,
            name: setlist.name,
            createdAt: setlist.createdAt,
            lastOpenedAt: setlist.lastOpenedAt,
            entries: entries
        )
    }

    private static func findSetlist(id: UUID, in context: ModelContext) throws -> Setlist? {
        var descriptor = FetchDescriptor<Setlist>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func sanitizedExportFolderName(from destinationURL: URL) -> String {
        var name = destinationURL.lastPathComponent
        let lower = name.lowercased()
        let packageSuffix = ".\(ProjectUTType.setlistPackageExtension)"
        if lower.hasSuffix(packageSuffix) {
            name = String(name.dropLast(packageSuffix.count))
        }
        return sanitizedFolderName(name)
    }

    private static func sanitizedFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Setlist" : trimmed
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

/// FileDocument wrapper so iOS/macOS can export a real folder via `fileExporter`.
struct SetlistPackageFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    static var writableContentTypes: [UTType] { [.folder] }

    nonisolated(unsafe) let fileWrapper: FileWrapper

    init(packageDirectory: URL) throws {
        fileWrapper = try FileWrapper(url: packageDirectory, options: .immediate)
        fileWrapper.filename = packageDirectory.lastPathComponent
    }

    init(configuration: ReadConfiguration) throws {
        fileWrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        fileWrapper
    }
}

struct ShowFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [ProjectUTType.showProjectType] }
    static var writableContentTypes: [UTType] { [ProjectUTType.showProjectType] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
