import Foundation
import SwiftData

struct SongProjectMetadata: Codable, Hashable {
    var bpm: Double?
    var timeSignatureNumerator: Int?
    var timeSignatureDenominator: Int?
    var baseKeyRaw: String?
    var transposeSemitones: Int
    var transposeHighQuality: Bool
    var smartGuideEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case bpm
        case timeSignatureNumerator
        case timeSignatureDenominator
        case baseKeyRaw
        case transposeSemitones
        case transposeHighQuality
        case smartGuideEnabled
    }

    init(from song: Song) {
        bpm = song.bpm
        timeSignatureNumerator = song.timeSignatureNumerator
        timeSignatureDenominator = song.timeSignatureDenominator
        baseKeyRaw = song.baseKeyRaw
        transposeSemitones = song.transposeSemitones
        transposeHighQuality = song.transposeHighQuality
        smartGuideEnabled = song.smartGuideEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm)
        timeSignatureNumerator = try container.decodeIfPresent(Int.self, forKey: .timeSignatureNumerator)
        timeSignatureDenominator = try container.decodeIfPresent(Int.self, forKey: .timeSignatureDenominator)
        baseKeyRaw = try container.decodeIfPresent(String.self, forKey: .baseKeyRaw)
        transposeSemitones = try container.decodeIfPresent(Int.self, forKey: .transposeSemitones) ?? 0
        transposeHighQuality = try container.decodeIfPresent(Bool.self, forKey: .transposeHighQuality) ?? false
        smartGuideEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartGuideEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(bpm, forKey: .bpm)
        try container.encodeIfPresent(timeSignatureNumerator, forKey: .timeSignatureNumerator)
        try container.encodeIfPresent(timeSignatureDenominator, forKey: .timeSignatureDenominator)
        try container.encodeIfPresent(baseKeyRaw, forKey: .baseKeyRaw)
        try container.encode(transposeSemitones, forKey: .transposeSemitones)
        try container.encode(transposeHighQuality, forKey: .transposeHighQuality)
        try container.encode(smartGuideEnabled, forKey: .smartGuideEnabled)
    }

    func apply(to song: Song) {
        song.bpm = bpm
        song.timeSignatureNumerator = timeSignatureNumerator
        song.timeSignatureDenominator = timeSignatureDenominator
        song.baseKeyRaw = baseKeyRaw
        song.transposeSemitones = transposeSemitones
        song.transposeHighQuality = transposeHighQuality
        song.smartGuideEnabled = smartGuideEnabled
    }
}

struct ProjectTrackMix: Codable, Hashable {
    var volume: Double
    var pan: Double
    var isMuted: Bool
    var isSolo: Bool
    var trimStartSeconds: Double
    var trimEndSeconds: Double?
    var excludeFromTranspose: Bool

    init(from track: AudioTrack) {
        volume = track.volume
        pan = track.pan
        isMuted = track.isMuted
        isSolo = track.isSolo
        trimStartSeconds = track.trimStartSeconds
        trimEndSeconds = track.trimEndSeconds
        excludeFromTranspose = track.excludeFromTranspose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decode(Double.self, forKey: .volume)
        pan = try container.decodeIfPresent(Double.self, forKey: .pan) ?? 0
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isSolo = try container.decode(Bool.self, forKey: .isSolo)
        trimStartSeconds = try container.decode(Double.self, forKey: .trimStartSeconds)
        trimEndSeconds = try container.decodeIfPresent(Double.self, forKey: .trimEndSeconds)
        excludeFromTranspose = try container.decode(Bool.self, forKey: .excludeFromTranspose)
    }

    func apply(to track: AudioTrack) {
        track.volume = volume
        track.pan = pan
        track.isMuted = isMuted
        track.isSolo = isSolo
        track.trimStartSeconds = trimStartSeconds
        track.trimEndSeconds = trimEndSeconds
        track.excludeFromTranspose = excludeFromTranspose
    }
}

struct ProjectTrack: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var sortOrder: Int
    var media: MediaReference
    var mix: ProjectTrackMix
    var groupName: String?
}

struct ProjectMIDITrack: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var sortOrder: Int
    var deviceName: String?
}

struct SongProjectArrangement: Codable {
    var markers: [ArrangementMarker]
    var sequence: SongArrangement
}

struct SongProjectDocument: Codable, Identifiable {
    static let currentFormatVersion = 2

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
    /// Read-only performance cache metadata. Audio files live under `Baked/`.
    var bakeManifest: SongBakeManifest?

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
        bakeManifest: SongBakeManifest? = nil
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
        self.bakeManifest = bakeManifest
    }
}
