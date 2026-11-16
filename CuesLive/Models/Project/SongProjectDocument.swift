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
    /// Missing from files written before the generated click.
    var click: ClickSettings

    enum CodingKeys: String, CodingKey {
        case bpm
        case timeSignatureNumerator
        case timeSignatureDenominator
        case baseKeyRaw
        case keyModeRaw
        case transposeSemitones
        case smartGuideEnabled
        case click
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm)
        timeSignatureNumerator = try container.decodeIfPresent(Int.self, forKey: .timeSignatureNumerator)
        timeSignatureDenominator = try container.decodeIfPresent(Int.self, forKey: .timeSignatureDenominator)
        baseKeyRaw = try container.decodeIfPresent(String.self, forKey: .baseKeyRaw)
        keyModeRaw = try container.decodeIfPresent(String.self, forKey: .keyModeRaw)
        transposeSemitones = try container.decodeIfPresent(Int.self, forKey: .transposeSemitones) ?? 0
        smartGuideEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartGuideEnabled) ?? false
        click = try container.decodeIfPresent(ClickSettings.self, forKey: .click) ?? ClickSettings()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(bpm, forKey: .bpm)
        try container.encodeIfPresent(timeSignatureNumerator, forKey: .timeSignatureNumerator)
        try container.encodeIfPresent(timeSignatureDenominator, forKey: .timeSignatureDenominator)
        try container.encodeIfPresent(baseKeyRaw, forKey: .baseKeyRaw)
        try container.encodeIfPresent(keyModeRaw, forKey: .keyModeRaw)
        try container.encode(transposeSemitones, forKey: .transposeSemitones)
        try container.encode(smartGuideEnabled, forKey: .smartGuideEnabled)
        try container.encode(click, forKey: .click)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decode(Double.self, forKey: .volume)
        pan = try container.decodeIfPresent(Double.self, forKey: .pan) ?? 0
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isSolo = try container.decode(Bool.self, forKey: .isSolo)
        trimStartSeconds = try container.decode(Double.self, forKey: .trimStartSeconds)
        trimEndSeconds = try container.decodeIfPresent(Double.self, forKey: .trimEndSeconds)
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

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case sortOrder
        case media
        case mix
        case groupName
        case sourceDurationSeconds
        case includeInKeyChange
        case laneHeight
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        media = try container.decode(MediaReference.self, forKey: .media)
        mix = try container.decode(ProjectTrackMix.self, forKey: .mix)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        sourceDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds)
        includeInKeyChange = try container.decodeIfPresent(Bool.self, forKey: .includeInKeyChange) ?? true
        laneHeight = try container.decodeIfPresent(Double.self, forKey: .laneHeight) ?? TrackLaneHeight.storedDefault
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(media, forKey: .media)
        try container.encode(mix, forKey: .mix)
        try container.encodeIfPresent(groupName, forKey: .groupName)
        try container.encodeIfPresent(sourceDurationSeconds, forKey: .sourceDurationSeconds)
        try container.encode(includeInKeyChange, forKey: .includeInKeyChange)
        try container.encode(laneHeight, forKey: .laneHeight)
    }
}

struct ProjectMIDITrack: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var sortOrder: Int
    var deviceName: String?
    var laneHeight: Double

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case sortOrder
        case deviceName
        case laneHeight
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        laneHeight = try container.decodeIfPresent(Double.self, forKey: .laneHeight) ?? TrackLaneHeight.storedDefault
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encode(laneHeight, forKey: .laneHeight)
    }
}

struct SongProjectArrangement: Codable {
    var markers: [ArrangementMarker]
    var clips: [TrackClip]
    /// Missing from files written before in and out points, which play the whole song.
    var playRange: SongPlayRange

    init(timeline: SongTimeline) {
        markers = timeline.markers
        clips = timeline.clips
        playRange = timeline.playRange
    }

    enum CodingKeys: String, CodingKey {
        case markers
        case clips
        case playRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markers = try container.decodeIfPresent([ArrangementMarker].self, forKey: .markers) ?? []
        clips = try container.decodeIfPresent([TrackClip].self, forKey: .clips) ?? []
        playRange = try container.decodeIfPresent(SongPlayRange.self, forKey: .playRange) ?? SongPlayRange()
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
    /// Optional, so files written before video support still decode.
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
