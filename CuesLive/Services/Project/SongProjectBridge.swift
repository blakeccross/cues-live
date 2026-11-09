import Foundation
import SwiftData

enum SongProjectBridge {
    enum BridgeError: LocalizedError {
        case missingProjectFile

        var errorDescription: String? {
            switch self {
            case .missingProjectFile:
                return "This song does not have a project file."
            }
        }
    }

    struct ProjectState {
        let timeline: SongTimeline
        let tempoChanges: [TempoChange]
        let timeSignatureChanges: [TimeSignatureChange]
        let midiEvents: [MIDIEvent]

        var markers: [ArrangementMarker] { timeline.sortedMarkers }
    }

    static func projectURL(for song: Song) -> URL? {
        guard let path = song.projectFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    @discardableResult
    static func ensureProjectFile(
        for song: Song,
        context: ModelContext
    ) throws -> URL {
        if let existing = projectURL(for: song) {
            return existing
        }

        let url = ProjectFileStore.defaultProjectURL(for: song.name)
        song.projectFilePath = url.path
        try context.save()

        let document = buildDocument(
            from: song,
            timeline: defaultTimeline(for: song),
            tempoChanges: defaultTempoChanges(for: song),
            timeSignatureChanges: defaultTimeSignatureChanges(for: song),
            midiEvents: []
        )
        try ProjectFileStore.save(document, to: url)
        return url
    }

    static func buildDocument(
        from song: Song,
        timeline: SongTimeline,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        midiEvents: [MIDIEvent],
        bakeManifest: SongBakeManifest? = nil
    ) -> SongProjectDocument {
        let tracks = song.sortedTracks.compactMap { track -> ProjectTrack? in
            guard let path = track.mediaPath, let style = track.mediaPathStyle else { return nil }
            let media = MediaReference(
                path: path,
                pathStyle: style,
                bookmark: track.mediaBookmarkData
            )
            return ProjectTrack(
                id: track.id,
                displayName: track.displayName,
                sortOrder: track.sortOrder,
                media: media,
                mix: ProjectTrackMix(from: track),
                groupName: track.group?.name,
                sourceDurationSeconds: track.sourceDurationSeconds
            )
        }

        let midiTracks = song.sortedMIDITracks.map { midiTrack in
            ProjectMIDITrack(
                id: midiTrack.id,
                displayName: midiTrack.displayName,
                sortOrder: midiTrack.sortOrder,
                deviceName: midiTrack.device?.name
            )
        }

        let trackIDs = Set(tracks.map(\.id))
        var storedTimeline = timeline
        storedTimeline.markers = timeline.sortedMarkers
        storedTimeline.clips = timeline.clips
            .filter { trackIDs.contains($0.trackID) }
            .sorted {
                $0.trackID == $1.trackID
                    ? $0.timelineStartSeconds < $1.timelineStartSeconds
                    : $0.trackID.uuidString < $1.trackID.uuidString
            }

        return SongProjectDocument(
            id: song.id,
            name: song.name,
            createdAt: song.createdAt,
            metadata: SongProjectMetadata(from: song),
            tracks: tracks,
            midiTracks: midiTracks,
            arrangement: SongProjectArrangement(timeline: storedTimeline),
            tempo: tempoChanges,
            timeSignatures: timeSignatureChanges,
            midiEvents: midiEvents,
            bakeManifest: bakeManifest
        )
    }

    static func syncProjectFile(
        for song: Song,
        context: ModelContext,
        timeline: SongTimeline? = nil,
        tempoChanges: [TempoChange]? = nil,
        timeSignatureChanges: [TimeSignatureChange]? = nil,
        midiEvents: [MIDIEvent]? = nil
    ) throws {
        let projectURL = try ensureProjectFile(for: song, context: context)
        let existingDocument = try? ProjectFileStore.load(from: projectURL)
        let resolvedTimeline = timeline
            ?? existingDocument.map { self.timeline(from: $0) }
            ?? defaultTimeline(for: song)
        let resolvedTempo = tempoChanges
            ?? normalizedTempoChanges(existingDocument?.tempo ?? [], for: song)
        let resolvedTimeSignatures = timeSignatureChanges
            ?? normalizedTimeSignatureChanges(existingDocument?.timeSignatures ?? [], for: song)
        let resolvedMIDIEvents = midiEvents ?? existingDocument?.midiEvents ?? []

        let document = buildDocument(
            from: song,
            timeline: addingClipsForNewTracks(
                to: resolvedTimeline,
                song: song,
                previousDocument: existingDocument
            ),
            tempoChanges: resolvedTempo,
            timeSignatureChanges: resolvedTimeSignatures,
            midiEvents: resolvedMIDIEvents,
            bakeManifest: existingDocument?.bakeManifest
        )
        try ProjectFileStore.save(document, to: projectURL)
        try context.save()
        try SongBakeStore.syncValidityOnPersist(for: song)
    }

    static func persist(
        song: Song,
        timeline: SongTimeline,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        midiEvents: [MIDIEvent],
        context: ModelContext
    ) throws {
        guard let projectURL = projectURL(for: song) else {
            throw BridgeError.missingProjectFile
        }

        let existingDocument = try? ProjectFileStore.load(from: projectURL)
        let document = buildDocument(
            from: song,
            timeline: addingClipsForNewTracks(
                to: timeline,
                song: song,
                previousDocument: existingDocument
            ),
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents,
            bakeManifest: existingDocument?.bakeManifest
        )
        try ProjectFileStore.save(document, to: projectURL)
        try context.save()
        try SongBakeStore.syncValidityOnPersist(for: song)
    }

    static func projectStateOrDefaults(for song: Song) -> ProjectState {
        if let state = try? loadProjectState(for: song) {
            return state
        }
        return ProjectState(
            timeline: defaultTimeline(for: song),
            tempoChanges: defaultTempoChanges(for: song),
            timeSignatureChanges: defaultTimeSignatureChanges(for: song),
            midiEvents: []
        )
    }

    static func loadProjectState(for song: Song) throws -> ProjectState {
        guard let projectURL = projectURL(for: song),
              FileManager.default.fileExists(atPath: projectURL.path) else {
            throw BridgeError.missingProjectFile
        }

        let document = try ProjectFileStore.load(from: projectURL)
        return ProjectState(
            timeline: timeline(from: document),
            tempoChanges: normalizedTempoChanges(document.tempo, for: song),
            timeSignatureChanges: normalizedTimeSignatureChanges(document.timeSignatures, for: song),
            midiEvents: document.midiEvents.sorted { $0.timelineSeconds < $1.timelineSeconds }
        )
    }

    static func timeline(from document: SongProjectDocument) -> SongTimeline {
        var timeline = document.arrangement.timeline
        timeline.markers = timeline.sortedMarkers
        return timeline
    }

    static func defaultTimeline(for song: Song) -> SongTimeline {
        SongTimeline(clips: song.sortedTracks.compactMap { defaultClip(for: $0, in: song) })
    }

    /// The track's trimmed file placed at the start of the timeline.
    static func defaultClip(for track: AudioTrack, in song: Song) -> TrackClip? {
        guard let sourceDuration = FileStore.sourceDuration(for: song, track: track) else { return nil }
        let start = min(max(track.trimStartSeconds, 0), sourceDuration)
        let end = min(track.trimEndSeconds ?? sourceDuration, sourceDuration)
        guard end - start >= TrackClip.minimumDuration else { return nil }
        return TrackClip(
            trackID: track.id,
            timelineStartSeconds: 0,
            duration: end - start,
            sourceStartSeconds: start
        )
    }

    /// Tracks added since the document was written start with their whole file on the timeline.
    static func addingClipsForNewTracks(
        to timeline: SongTimeline,
        song: Song,
        previousDocument: SongProjectDocument?
    ) -> SongTimeline {
        let knownTrackIDs = Set(previousDocument?.tracks.map(\.id) ?? [])
            .union(timeline.clips.map(\.trackID))
        var result = timeline
        for track in song.sortedTracks where !knownTrackIDs.contains(track.id) {
            if let clip = defaultClip(for: track, in: song) {
                result.clips.append(clip)
            }
        }
        return result
    }

    static func defaultTempoChanges(for song: Song) -> [TempoChange] {
        [TempoChange(startMeasure: 1, bpm: song.bpm ?? TempoChange.defaultBPM)]
            .normalizedEnsuringInitialMarker(defaultBPM: song.bpm ?? TempoChange.defaultBPM)
    }

    static func defaultTimeSignatureChanges(for song: Song) -> [TimeSignatureChange] {
        [
            TimeSignatureChange(
                numerator: song.timeSignatureNumerator ?? TimeSignatureChange.defaultNumerator,
                denominator: song.timeSignatureDenominator ?? TimeSignatureChange.defaultDenominator,
                startMeasure: 1
            )
        ]
        .normalizedEnsuringInitialMarker(
            defaultNumerator: song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator,
            defaultDenominator: song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
        )
    }

    static func normalizedTempoChanges(_ changes: [TempoChange], for song: Song) -> [TempoChange] {
        changes.normalizedEnsuringInitialMarker(defaultBPM: song.bpm ?? TempoChange.defaultBPM)
    }

    static func normalizedTimeSignatureChanges(_ changes: [TimeSignatureChange], for song: Song) -> [TimeSignatureChange] {
        changes.normalizedEnsuringInitialMarker(
            defaultNumerator: song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator,
            defaultDenominator: song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
        )
    }

    static func applyDocument(
        _ document: SongProjectDocument,
        to song: Song,
        projectURL: URL,
        context: ModelContext
    ) throws {
        song.id = document.id
        song.name = document.name
        song.createdAt = document.createdAt
        document.metadata.apply(to: song)
        song.projectFilePath = projectURL.path

        let existingTracks = song.tracks
        for track in existingTracks {
            context.delete(track)
        }
        song.tracks.removeAll()

        for projectTrack in document.tracks.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let track = AudioTrack(
                displayName: projectTrack.displayName,
                relativeFilePath: displayFileName(for: projectTrack.media),
                sortOrder: projectTrack.sortOrder
            )
            track.id = projectTrack.id
            applyMediaReference(projectTrack.media, to: track)
            projectTrack.mix.apply(to: track)
            track.sourceDurationSeconds = projectTrack.sourceDurationSeconds
            if let groupName = projectTrack.groupName {
                track.group = TrackGroupStore.findOrCreateGroup(named: groupName, in: context)
            }
            track.song = song
            context.insert(track)
            song.tracks.append(track)
        }

        let existingMIDITracks = song.midiTracks
        for midiTrack in existingMIDITracks {
            context.delete(midiTrack)
        }
        song.midiTracks.removeAll()

        for projectMIDITrack in document.midiTracks.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let midiTrack = MIDITrack(
                displayName: projectMIDITrack.displayName,
                sortOrder: projectMIDITrack.sortOrder
            )
            midiTrack.id = projectMIDITrack.id
            if let deviceName = projectMIDITrack.deviceName {
                midiTrack.device = MIDIDeviceStore.findDevice(named: deviceName, in: context)
            }
            midiTrack.song = song
            context.insert(midiTrack)
            song.midiTracks.append(midiTrack)
        }

        try context.save()
    }

    @discardableResult
    static func importProject(
        from url: URL,
        into context: ModelContext
    ) throws -> Song {
        let document = try ProjectFileStore.load(from: url)
        if let existing = try findSong(id: document.id, in: context) {
            try applyDocument(document, to: existing, projectURL: url, context: context)
            return existing
        }

        let song = Song(name: document.name)
        song.id = document.id
        song.createdAt = document.createdAt
        context.insert(song)
        try applyDocument(document, to: song, projectURL: url, context: context)
        return song
    }

    static func buildShowDocument(
        from setlist: Setlist,
        showFileURL: URL
    ) throws -> ShowProjectDocument {
        let entries = setlist.sortedEntries.compactMap { entry -> ShowProjectEntry? in
            if entry.isHeader, let headerTitle = entry.headerTitle {
                return ShowProjectEntry(
                    sortOrder: entry.sortOrder,
                    headerTitle: headerTitle,
                    headerTimeSeconds: entry.headerTimeSeconds
                )
            }

            guard let song = entry.song,
                  let path = song.projectFilePath else {
                return nil
            }
            let projectURL = URL(fileURLWithPath: path)
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

    @discardableResult
    static func importShow(
        from url: URL,
        into context: ModelContext
    ) throws -> Setlist {
        let document = try ShowFileStore.load(from: url)

        if let existing = try findSetlist(id: document.id, in: context) {
            existing.showFilePath = url.path
            existing.showFileBookmark = MediaReferenceResolver.makeBookmark(for: url)
            if existing.entries.isEmpty {
                try importShowEntries(from: document, showFileURL: url, into: existing, context: context)
                try context.save()
            }
            return existing
        }

        let isDraft = document.name.trimmingCharacters(in: .whitespacesAndNewlines) == Setlist.untitledName
        let setlist = Setlist(name: document.name, isDraft: isDraft)
        setlist.id = document.id
        setlist.createdAt = document.createdAt
        setlist.lastOpenedAt = document.lastOpenedAt
        setlist.showFilePath = url.path
        setlist.showFileBookmark = MediaReferenceResolver.makeBookmark(for: url)
        context.insert(setlist)

        try importShowEntries(from: document, showFileURL: url, into: setlist, context: context)
        try context.save()
        return setlist
    }

    static func importShowEntries(
        from document: ShowProjectDocument,
        showFileURL: URL,
        into setlist: Setlist,
        context: ModelContext
    ) throws {
        for showEntry in document.entries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if showEntry.isHeader, let headerTitle = showEntry.headerTitle {
                let entry = SetlistEntry(
                    sortOrder: showEntry.sortOrder,
                    headerTitle: headerTitle,
                    headerTimeSeconds: showEntry.headerTimeSeconds
                )
                entry.setlist = setlist
                context.insert(entry)
                setlist.entries.append(entry)
                continue
            }

            guard let songProject = showEntry.songProject,
                  let projectURL = MediaReferenceResolver.resolve(
                    songProject,
                    showFileURL: showFileURL
                  ) else {
                continue
            }

            let song = try importProject(from: projectURL, into: context)
            let entry = SetlistEntry(
                sortOrder: showEntry.sortOrder,
                song: song,
                transition: showEntry.transitionValue
            )
            if showEntry.transitionValue == .overlap {
                entry.overlapConfig = showEntry.overlap
            }
            entry.setlist = setlist
            context.insert(entry)
            setlist.entries.append(entry)
        }
    }

    static func restoreShowsFromDisk(in context: ModelContext) {
        let showsDirectory = ShowFileStore.showsDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: showsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where url.pathExtension == ProjectUTType.showProjectExtension {
            _ = try? importShow(from: url, into: context)
        }
    }

    static func persistShow(
        for setlist: Setlist,
        to url: URL? = nil,
        context: ModelContext
    ) throws {
        let previousPath = setlist.showFilePath
        let showURL = resolvedShowWriteURL(for: setlist, preferred: url)
        let didAccess = showURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                showURL.stopAccessingSecurityScopedResource()
            }
        }

        for entry in setlist.sortedEntries {
            guard let song = entry.song else { continue }
            try ensureProjectFile(for: song, context: context)
        }

        let document = try buildShowDocument(from: setlist, showFileURL: showURL)
        try ShowFileStore.save(document, to: showURL)
        setlist.showFilePath = showURL.path
        setlist.showFileBookmark = MediaReferenceResolver.makeBookmark(for: showURL)
        try context.save()
        removeReplacedDefaultShow(previousPath: previousPath, newURL: showURL)
    }

    static func encodedShowData(for setlist: Setlist, context: ModelContext) throws -> Data {
        let showURL = resolvedShowWriteURL(for: setlist, preferred: nil)
        for entry in setlist.sortedEntries {
            guard let song = entry.song else { continue }
            try ensureProjectFile(for: song, context: context)
        }
        let document = try buildShowDocument(from: setlist, showFileURL: showURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private static func resolvedShowWriteURL(for setlist: Setlist, preferred: URL?) -> URL {
        if let preferred {
            return preferred
        }
        if let bookmark = setlist.showFileBookmark {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = MediaReferenceResolver.usesSecurityScopedBookmarks
                ? [.withSecurityScope]
                : []
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        if let path = setlist.showFilePath {
            return URL(fileURLWithPath: path)
        }
        return ShowFileStore.defaultShowURL(for: setlist.name)
    }

    private static func removeReplacedDefaultShow(previousPath: String?, newURL: URL) {
        guard let previousPath, previousPath != newURL.path else { return }
        let previousURL = URL(fileURLWithPath: previousPath).standardizedFileURL
        let showsDirectory = ShowFileStore.showsDirectory.standardizedFileURL
        guard previousURL.deletingLastPathComponent() == showsDirectory else { return }
        try? FileManager.default.removeItem(at: previousURL)
    }

    private static func displayFileName(for media: MediaReference) -> String {
        URL(fileURLWithPath: media.path).lastPathComponent
    }

    private static func applyMediaReference(_ reference: MediaReference, to track: AudioTrack) {
        track.mediaPath = reference.path
        track.mediaPathStyle = reference.pathStyle
        track.mediaBookmarkData = reference.bookmark
        track.relativeFilePath = displayFileName(for: reference)
    }

    private static func findSong(id: UUID, in context: ModelContext) throws -> Song? {
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func findSetlist(id: UUID, in context: ModelContext) throws -> Setlist? {
        var descriptor = FetchDescriptor<Setlist>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
