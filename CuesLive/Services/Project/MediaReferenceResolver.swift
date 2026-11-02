import Foundation

enum MediaReferenceResolver {
    #if os(macOS)
    static let usesSecurityScopedBookmarks: Bool = {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }()
    #else
    static let usesSecurityScopedBookmarks = false
    #endif

    static func makeBookmark(for url: URL) -> Data? {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = usesSecurityScopedBookmarks ? [.withSecurityScope] : []
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        return try? url.bookmarkData(
            options: options,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        #if os(macOS)
        let resolutionOptions: [URL.BookmarkResolutionOptions] = usesSecurityScopedBookmarks
            ? [.withSecurityScope]
            : [[], [.withSecurityScope]]
        #else
        let resolutionOptions: [URL.BookmarkResolutionOptions] = [[]]
        #endif

        for options in resolutionOptions {
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            if usesSecurityScopedBookmarks {
                guard url.startAccessingSecurityScopedResource() else { continue }
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                if usesSecurityScopedBookmarks {
                    url.stopAccessingSecurityScopedResource()
                }
                continue
            }

            return url
        }

        return nil
    }

    static func relativePath(from url: URL, to projectFileURL: URL) -> String? {
        let projectDirectory = projectFileURL.deletingLastPathComponent().standardizedFileURL
        let target = url.standardizedFileURL
        let projectPath = projectDirectory.path
        let targetPath = target.path
        guard targetPath.hasPrefix(projectPath) else { return nil }
        var relative = String(targetPath.dropFirst(projectPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative.isEmpty ? nil : relative
    }

    static func resolve(
        _ reference: MediaReference,
        projectFileURL: URL?
    ) -> URL? {
        if let bookmark = reference.bookmark,
           let url = resolveBookmark(bookmark),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        if reference.pathStyle == .relativeToProject,
           let projectFileURL {
            let candidate = projectFileURL
                .deletingLastPathComponent()
                .appendingPathComponent(reference.path)
                .standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let candidate = URL(fileURLWithPath: reference.path).standardizedFileURL
        #if os(macOS)
        guard !usesSecurityScopedBookmarks || FileStore.isInAppContainer(candidate) else {
            return nil
        }
        #endif
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    static func resolve(
        _ reference: ProjectDocumentReference,
        showFileURL: URL?
    ) -> URL? {
        if let bookmark = reference.bookmark,
           let url = resolveBookmark(bookmark),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        if reference.pathStyle == .relativeToProject,
           let showFileURL {
            let candidate = showFileURL
                .deletingLastPathComponent()
                .appendingPathComponent(reference.path)
                .standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let candidate = URL(fileURLWithPath: reference.path).standardizedFileURL
        #if os(macOS)
        guard !usesSecurityScopedBookmarks || FileStore.isInAppContainer(candidate) else {
            return nil
        }
        #endif
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    static func refreshBookmark(for reference: inout MediaReference, resolvedURL: URL, projectFileURL: URL?) {
        reference.bookmark = makeBookmark(for: resolvedURL)
        if let projectFileURL,
           let relative = relativePath(from: resolvedURL, to: projectFileURL) {
            reference.path = relative
            reference.pathStyle = .relativeToProject
        } else {
            reference.path = resolvedURL.path
            reference.pathStyle = .absolute
        }
    }
}
