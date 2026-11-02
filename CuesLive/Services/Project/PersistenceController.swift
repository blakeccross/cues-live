import Foundation
import OSLog
import SwiftData

enum PersistenceController {
    /// Bump when arrangement marker storage changes so stale rows are discarded.
    private static let storeVersion = 21
    private static let storeVersionKey = "SwiftDataStoreVersion"
    private static let logger = Logger(subsystem: "live.cues", category: "Persistence")
    private static let storeDirectoryName = "live.cues"
    private static let storeFileName = "CuesLive.store"

    static let modelTypes: [any PersistentModel.Type] = [
        Song.self,
        AudioTrack.self,
        MIDITrack.self,
        MIDIDevice.self,
        TrackGroup.self,
        OutputRoutingConfig.self,
        GroupOutputRoute.self,
        TimecodeSettings.self,
        Setlist.self,
        SetlistEntry.self,
    ]

    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let storeURL = try resolvedStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        migrateStoreIfNeeded(at: storeURL)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seedLaunchData(in: container)
            return container
        } catch {
            logger.error("SwiftData store open failed; removing store and retrying: \(error.localizedDescription, privacy: .public)")
            resetStore(at: storeURL, reason: "ModelContainer open failed")
            UserDefaults.standard.set(storeVersion, forKey: storeVersionKey)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seedLaunchData(in: container)
            return container
        }
    }

    /// Inserts first-run records before any SwiftUI `@Query` attaches.
    /// Writing these from `onAppear` / `.task` races SwiftData's fetch executor
    /// on a cold store and can SIGSEGV (null deref in SwiftData).
    @MainActor
    private static func seedLaunchData(in container: ModelContainer) {
        let context = container.mainContext
        TrackGroupStore.ensureDefaults(in: context)
        OutputRoutingStore.ensureConfig(in: context)
        TimecodeSettingsStore.ensureConfig(in: context)
        SongProjectBridge.restoreShowsFromDisk(in: context)

        let setlists = (try? context.fetch(FetchDescriptor<Setlist>())) ?? []
        if setlists.isEmpty {
            context.insert(Setlist.untitledDraft())
            try? context.save()
        }
    }

    /// App-specific store under Application Support. Never use the unnamed
    /// SwiftData default (`…/Application Support/default.store`), which collides
    /// with other unsandboxed apps on the same machine.
    private static func resolvedStoreURL() throws -> URL {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directory = applicationSupport.appendingPathComponent(storeDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    private static func migrateStoreIfNeeded(at url: URL) {
        let storedVersion = UserDefaults.standard.integer(forKey: storeVersionKey)
        guard storedVersion < storeVersion else { return }

        logger.notice("Resetting SwiftData store for schema migration \(storedVersion, privacy: .public) → \(self.storeVersion, privacy: .public)")
        resetStore(at: url, reason: "schema version migration")
        UserDefaults.standard.set(storeVersion, forKey: storeVersionKey)
    }

    private static func resetStore(at url: URL, reason: String) {
        let fileManager = FileManager.default
        let relatedURLs = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal"),
        ]

        for storeURL in relatedURLs where fileManager.fileExists(atPath: storeURL.path) {
            logger.error("Removing SwiftData file (\(reason, privacy: .public)): \(storeURL.path, privacy: .public)")
            try? fileManager.removeItem(at: storeURL)
        }
    }
}
