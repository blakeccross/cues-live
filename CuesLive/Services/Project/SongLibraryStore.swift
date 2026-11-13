import Foundation
import SwiftData

/// Library-level song operations: deleting and duplicating songs along with their project files.
@MainActor
enum SongLibraryStore {
    /// Deletes the songs, their setlist entries, and their `.cueslive` project files.
    /// Project files are only removed once the store save succeeds.
    static func delete(_ songs: [Song], context: ModelContext) throws {
        guard !songs.isEmpty else { return }
        let songIDs = Set(songs.map(\.id))

        let entries = try context.fetch(FetchDescriptor<SetlistEntry>())
        for entry in entries {
            guard let songID = entry.song?.id, songIDs.contains(songID) else { continue }
            entry.setlist?.entries.removeAll { $0 === entry }
            context.delete(entry)
        }

        for song in songs {
            context.delete(song)
        }

        try context.save()
        for song in songs {
            FileStore.deleteProjectFile(for: song)
        }
    }

    /// Copies a song, its tracks, and its project state under an unused "Copy" name.
    @discardableResult
    static func duplicate(_ source: Song, existingNames: Set<String>, context: ModelContext) throws -> Song {
        let copy = Song(name: duplicateName(for: source.name, existingNames: existingNames))
        copy.bpm = source.bpm
        copy.timeSignatureNumerator = source.timeSignatureNumerator
        copy.timeSignatureDenominator = source.timeSignatureDenominator
        copy.baseKeyRaw = source.baseKeyRaw
        copy.transposeSemitones = source.transposeSemitones
        copy.smartGuideEnabled = source.smartGuideEnabled
        context.insert(copy)

        do {
            let trackIDMap = copyTracks(from: source, to: copy, context: context)
            let sourceState = try SongProjectBridge.loadProjectState(for: source)
            var timeline = sourceState.timeline
            timeline.clips = timeline.clips.map { clip in
                TrackClip(
                    trackID: trackIDMap[clip.trackID] ?? clip.trackID,
                    timelineStartSeconds: clip.timelineStartSeconds,
                    duration: clip.duration,
                    sourceStartSeconds: clip.sourceStartSeconds,
                    gainDB: clip.gainDB,
                    playbackRate: clip.playbackRate
                )
            }
            let midiEvents = sourceState.midiEvents.map { event in
                MIDIEvent(
                    id: event.id,
                    trackID: trackIDMap[event.trackID] ?? event.trackID,
                    timelineSeconds: event.timelineSeconds,
                    commandID: event.commandID,
                    label: event.label
                )
            }

            try context.save()
            try SongProjectBridge.syncProjectFile(
                for: copy,
                context: context,
                timeline: timeline,
                tempoChanges: sourceState.tempoChanges,
                timeSignatureChanges: sourceState.timeSignatureChanges,
                midiEvents: midiEvents
            )
            return copy
        } catch {
            context.delete(copy)
            FileStore.deleteProjectFile(for: copy)
            throw error
        }
    }

    /// `"Name Copy"`, then `"Name Copy 2"`, `"Name Copy 3"`… skipping names already taken.
    static func duplicateName(for baseName: String, existingNames: Set<String>) -> String {
        let firstCandidate = "\(baseName) Copy"
        if !existingNames.contains(firstCandidate) {
            return firstCandidate
        }

        var index = 2
        while existingNames.contains("\(baseName) Copy \(index)") {
            index += 1
        }
        return "\(baseName) Copy \(index)"
    }

    /// Returns a map from each source track ID to its copy's ID.
    private static func copyTracks(from source: Song, to copy: Song, context: ModelContext) -> [UUID: UUID] {
        var trackIDMap: [UUID: UUID] = [:]
        for track in source.sortedTracks {
            let newTrack = AudioTrack(
                displayName: track.displayName,
                relativeFilePath: track.relativeFilePath,
                sortOrder: track.sortOrder
            )
            trackIDMap[track.id] = newTrack.id
            newTrack.volume = track.volume
            newTrack.pan = track.pan
            newTrack.isMuted = track.isMuted
            newTrack.isSolo = track.isSolo
            newTrack.trimStartSeconds = track.trimStartSeconds
            newTrack.trimEndSeconds = track.trimEndSeconds
            newTrack.includeInKeyChange = track.includeInKeyChange
            newTrack.sourceDurationSeconds = track.sourceDurationSeconds
            newTrack.mediaPath = track.mediaPath
            newTrack.mediaPathStyle = track.mediaPathStyle
            newTrack.mediaBookmarkData = track.mediaBookmarkData
            newTrack.group = track.group
            newTrack.song = copy
            context.insert(newTrack)
            copy.tracks.append(newTrack)
        }
        return trackIDMap
    }
}
