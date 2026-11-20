import Foundation
import SwiftData

struct SongProjectMetadata: Codable, Hashable {
    var bpm: Double?
    var timeSignatureNumerator: Int?
    var timeSignatureDenominator: Int?
    var baseKeyRaw: String?
    var keyModeRaw: String?
    var transposeSemitones: Int
    var smartGuideEnabled: Bool
    var click: ClickSettings

    init(from song: Song) {
        bpm = song.bpm
        timeSignatureNumerator = song.timeSignatureNumerator
        timeSignatureDenominator = song.timeSignatureDenominator
        baseKeyRaw = song.baseKeyRaw
        keyModeRaw = song.keyModeRaw
        transposeSemitones = song.transposeSemitones
        smartGuideEnabled = song.smartGuideEnabled
        click = song.clickSettings
    }

    func apply(to song: Song) {
        song.bpm = bpm
        song.timeSignatureNumerator = timeSignatureNumerator
        song.timeSignatureDenominator = timeSignatureDenominator
        song.baseKeyRaw = baseKeyRaw
        song.keyModeRaw = keyModeRaw
        song.transposeSemitones = transposeSemitones
        song.smartGuideEnabled = smartGuideEnabled
        song.clickSettings = click
    }
}

struct ProjectTrackMix: Codable, Hashable {
    var volume: Double
    var pan: Double
    var isMuted: Bool
    var isSolo: Bool
    var trimStartSeconds: Double
    var trimEndSeconds: Double?

    init(from track: AudioTrack) {
        volume = track.volume
        pan = track.pan
        isMuted = track.isMuted
        isSolo = track.isSolo
        trimStartSeconds = track.trimStartSeconds
        trimEndSeconds = track.trimEndSeconds
    }

    func apply(to track: AudioTrack) {
        track.volume = volume
        track.pan = pan
        track.isMuted = isMuted
        track.isSolo = isSolo
        track.trimStartSeconds = trimStartSeconds
        track.trimEndSeconds = trimEndSeconds
    }
}

struct ProjectTrack: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var sortOrder: Int
    var media: MediaReference
    var mix: ProjectTrackMix
    var groupName: String?
    /// Cached source length so sections keep their size when the audio file is missing.
    var sourceDurationSeconds: Double?
    var includeInKeyChange: Bool
    var laneHeight: Double

    init(
        id: UUID,
        displayName: String,
        sortOrder: Int,
        media: MediaReference,
        mix: ProjectTrackMix,
        groupName: String?,
        sourceDurationSeconds: Double?,
        includeInKeyChange: Bool = true,
        laneHeight: Double = TrackLaneHeight.storedDefault
    ) {
        self.id = id
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.media = media
        self.mix = mix
        self.groupName = groupName
        self.sourceDurationSeconds = sourceDurationSeconds
        self.includeInKeyChange = includeInKeyChange
        self.laneHeight = laneHeight
    }
}

struct ProjectMIDITrack: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var sortOrder: Int
    var deviceName: String?
    var laneHeight: Double

    init(
        id: UUID,
        displayName: String,
        sortOrder: Int,
        deviceName: String?,
        laneHeight: Double = TrackLaneHeight.storedDefault
    ) {
        self.id = id
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.deviceName = deviceName
        self.laneHeight = laneHeight
    }
}

struct SongProjectArrangement: Codable {
    var markers: [ArrangementMarker]
    var clips: [TrackClip]
    var playRange: SongPlayRange

    init(timeline: SongTimeline) {
        markers = timeline.markers
        clips = timeline.clips
        playRange = timeline.playRange
    }

    var timeline: SongTimeline {
        SongTimeline(markers: markers, clips: clips, playRange: playRange)
    }
}

struct SongProjectDocument: Codable, Identifiable {
    static let currentFormatVersion = 3

    var formatVersion: Int
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var metadata: SongProjectMetadata
    var tracks: [ProjectTrack]
    var midiTracks: [ProjectMIDITrack]
    var arrangement: SongProjectArrangement
    var tempo: [TempoChange]
    var timeSignatures: [TimeSignatureChange]
    var midiEvents: [MIDIEvent]
    /// Nil when the song has no movie.
    var video: ProjectVideoTrack?

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        modifiedAt: Date = Date(),
        metadata: SongProjectMetadata,
        tracks: [ProjectTrack] = [],
        midiTracks: [ProjectMIDITrack] = [],
        arrangement: SongProjectArrangement,
        tempo: [TempoChange] = [],
        timeSignatures: [TimeSignatureChange] = [],
        midiEvents: [MIDIEvent] = [],
        video: ProjectVideoTrack? = nil
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.metadata = metadata
        self.tracks = tracks
        self.midiTracks = midiTracks
        self.arrangement = arrangement
        self.tempo = tempo
        self.timeSignatures = timeSignatures
        self.midiEvents = midiEvents
        self.video = video
    }
}
