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
    /// Semitone offset baked into included stems. Zero plays the original files.
    var transposeSemitones: Int = 0
    var smartGuideEnabled: Bool = false
    var projectFilePath: String?

    @Relationship(deleteRule: .cascade, inverse: \AudioTrack.song)
    var tracks: [AudioTrack]

    @Relationship(deleteRule: .cascade, inverse: \MIDITrack.song)
    var midiTracks: [MIDITrack]

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
        bpm = nil
        timeSignatureNumerator = nil
        timeSignatureDenominator = nil
        baseKeyRaw = nil
        transposeSemitones = 0
        smartGuideEnabled = false
        projectFilePath = nil
        tracks = []
        midiTracks = []
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

    var sortedTracks: [AudioTrack] {
        tracks.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedMIDITracks: [MIDITrack] {
        midiTracks.sorted { $0.sortOrder < $1.sortOrder }
    }
}
