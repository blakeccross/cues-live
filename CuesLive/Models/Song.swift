import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID
    var name: String
    var createdAt: Date
    var bpm: Double?
    var timeSignatureNumerator: Int?
    var timeSignatureDenominator: Int?
    /// User-selected root pitch class (`SongMusicalKey.rawValue`). Displayed key applies `transposeSemitones`.
    var baseKeyRaw: String?
    /// `SongKeyMode.rawValue`; nil means major.
    var keyModeRaw: String?
    /// Semitone offset baked into included stems. Zero plays the original files.
    var transposeSemitones: Int = 0
    var smartGuideEnabled: Bool = false
    var clickEnabled: Bool = false
    /// `ClickRhythm.rawValue`; nil means auto.
    var clickRhythmRaw: String?
    /// `ClickSound.rawValue`; nil means the default sound.
    var clickSoundRaw: String?
    var projectFilePath: String?
    /// Library folder; nil keeps the song only in All Songs.
    var folder: SongFolder?

    @Relationship(deleteRule: .cascade, inverse: \AudioTrack.song)
    var tracks: [AudioTrack]

    @Relationship(deleteRule: .cascade, inverse: \MIDITrack.song)
    var midiTracks: [MIDITrack]

    /// The movie shown in the Video window while this song plays.
    @Relationship(deleteRule: .cascade, inverse: \VideoTrack.song)
    var videoTrack: VideoTrack?

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
        bpm = nil
        timeSignatureNumerator = nil
        timeSignatureDenominator = nil
        baseKeyRaw = nil
        keyModeRaw = nil
        transposeSemitones = 0
        smartGuideEnabled = false
        projectFilePath = nil
        folder = nil
        tracks = []
        midiTracks = []
        videoTrack = nil
    }

    var timeSignatureDisplay: String? {
        guard let numerator = timeSignatureNumerator,
              let denominator = timeSignatureDenominator,
              numerator > 0,
              denominator > 0 else {
            return nil
        }
        return "\(numerator)/\(denominator)"
    }

    var clickSettings: ClickSettings {
        get {
            ClickSettings(
                isEnabled: clickEnabled,
                rhythm: clickRhythmRaw.flatMap(ClickRhythm.init(rawValue:)) ?? .auto,
                sound: clickSoundRaw.flatMap(ClickSound.init(rawValue:)) ?? .standard
            )
        }
        set {
            clickEnabled = newValue.isEnabled
            clickRhythmRaw = newValue.rhythm.rawValue
            clickSoundRaw = newValue.sound.rawValue
        }
    }

    var sortedTracks: [AudioTrack] {
        tracks.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedMIDITracks: [MIDITrack] {
        midiTracks.sorted { $0.sortOrder < $1.sortOrder }
    }
}
