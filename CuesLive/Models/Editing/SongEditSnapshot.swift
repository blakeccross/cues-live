import Foundation
import SwiftData

struct TrackEditSnapshot: Equatable, Hashable {
    let trackID: UUID
    var displayName: String
    var relativeFilePath: String
    var sortOrder: Int
    var mediaPath: String?
    var mediaPathStyleRaw: String?
    var mediaBookmarkData: Data?
    var volume: Double
    var pan: Double
    var isMuted: Bool
    var isSolo: Bool
    var trimStartSeconds: Double
    var trimEndSeconds: Double?
    var groupName: String?
}

struct SongMetadataSnapshot: Equatable, Hashable {
    var bpm: Double?
    var timeSignatureNumerator: Int?
    var timeSignatureDenominator: Int?
    var baseKeyRaw: String?
    var smartGuideEnabled: Bool
}

struct SongEditSnapshot: Equatable {
    var timeline: SongTimeline
    var tempoChanges: [TempoChange]
    var timeSignatureChanges: [TimeSignatureChange]
    var midiEvents: [MIDIEvent]
    var songMetadata: SongMetadataSnapshot
    var tracks: [TrackEditSnapshot]

    static func capture(
        song: Song,
        timeline: SongTimeline,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        midiEvents: [MIDIEvent]
    ) -> SongEditSnapshot {
        SongEditSnapshot(
            timeline: timeline,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            midiEvents: midiEvents,
            songMetadata: SongMetadataSnapshot(
                bpm: song.bpm,
                timeSignatureNumerator: song.timeSignatureNumerator,
                timeSignatureDenominator: song.timeSignatureDenominator,
                baseKeyRaw: song.baseKeyRaw,
                smartGuideEnabled: song.smartGuideEnabled
            ),
            tracks: song.sortedTracks.map { track in
                TrackEditSnapshot(
                    trackID: track.id,
                    displayName: track.displayName,
                    relativeFilePath: track.relativeFilePath,
                    sortOrder: track.sortOrder,
                    mediaPath: track.mediaPath,
                    mediaPathStyleRaw: track.mediaPathStyleRaw,
                    mediaBookmarkData: track.mediaBookmarkData,
                    volume: track.volume,
                    pan: track.pan,
                    isMuted: track.isMuted,
                    isSolo: track.isSolo,
                    trimStartSeconds: track.trimStartSeconds,
                    trimEndSeconds: track.trimEndSeconds,
                    groupName: track.group?.name
                )
            }
        )
    }

    func applyMetadata(to song: Song) {
        song.bpm = songMetadata.bpm
        song.timeSignatureNumerator = songMetadata.timeSignatureNumerator
        song.timeSignatureDenominator = songMetadata.timeSignatureDenominator
        song.baseKeyRaw = songMetadata.baseKeyRaw
        song.smartGuideEnabled = songMetadata.smartGuideEnabled
    }

    func applyTracks(to song: Song, context: ModelContext) {
        let groups = (try? context.fetch(FetchDescriptor<TrackGroup>())) ?? []
        let groupsByName = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0) })
        let snapshotIDs = Set(tracks.map(\.trackID))

        for trackSnapshot in tracks {
            let track: AudioTrack
            if let existing = song.sortedTracks.first(where: { $0.id == trackSnapshot.trackID }) {
                track = existing
            } else {
                track = AudioTrack(
                    displayName: trackSnapshot.displayName,
                    relativeFilePath: trackSnapshot.relativeFilePath,
                    sortOrder: trackSnapshot.sortOrder
                )
                track.id = trackSnapshot.trackID
                track.song = song
                context.insert(track)
                song.tracks.append(track)
            }

            track.displayName = trackSnapshot.displayName
            track.relativeFilePath = trackSnapshot.relativeFilePath
            track.sortOrder = trackSnapshot.sortOrder
            track.mediaPath = trackSnapshot.mediaPath
            track.mediaPathStyleRaw = trackSnapshot.mediaPathStyleRaw
            track.mediaBookmarkData = trackSnapshot.mediaBookmarkData
            track.volume = trackSnapshot.volume
            track.pan = trackSnapshot.pan
            track.isMuted = trackSnapshot.isMuted
            track.isSolo = trackSnapshot.isSolo
            track.trimStartSeconds = trackSnapshot.trimStartSeconds
            track.trimEndSeconds = trackSnapshot.trimEndSeconds
            if let groupName = trackSnapshot.groupName {
                track.group = groupsByName[groupName]
            } else {
                track.group = nil
            }
        }

        for track in song.sortedTracks where !snapshotIDs.contains(track.id) {
            song.tracks.removeAll { $0.id == track.id }
            context.delete(track)
        }
    }

    func normalizedTempoChanges(defaultBPM: Double) -> [TempoChange] {
        tempoChanges.normalizedEnsuringInitialMarker(defaultBPM: defaultBPM)
    }

    func normalizedTimeSignatureChanges(
        defaultNumerator: Int,
        defaultDenominator: Int
    ) -> [TimeSignatureChange] {
        timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: defaultNumerator,
            defaultDenominator: defaultDenominator
        )
    }
}
