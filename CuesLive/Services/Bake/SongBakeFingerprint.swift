import CryptoKit
import Foundation
import SwiftData

enum SongBakeFingerprint {
  /// Minimum track count before bake prompts / baked playback are considered worthwhile.
  static let performanceTrackThreshold = 20

  static func compute(
    for song: Song,
    projectState: SongProjectBridge.ProjectState,
    trackModificationDates: [UUID: Date] = [:]
  ) -> String {
    var parts: [String] = []

    parts.append("song|\(song.id.uuidString)")
    parts.append("transpose|\(song.transposeSemitones)|\(song.transposeHighQuality)")

  parts.append("tempo|\(fingerprint(tempoChanges: projectState.tempoChanges))")
  parts.append("meter|\(fingerprint(timeSignatures: projectState.timeSignatureChanges))")
  parts.append("midi|\(fingerprint(midiEvents: projectState.midiEvents))")
  parts.append("timeline|\(fingerprint(timeline: projectState.timeline))")

    let sortedTracks = song.sortedTracks.sorted { $0.sortOrder < $1.sortOrder }
    for track in sortedTracks {
      let modDate = trackModificationDates[track.id] ?? .distantPast
      let modToken = Int(modDate.timeIntervalSince1970)
      let mediaPath = track.mediaPath ?? track.relativeFilePath
      let groupID = track.group?.id.uuidString ?? "ungrouped"
      let trimEnd = track.trimEndSeconds.map { String($0) } ?? "nil"
      // Pan is appended only when off-centre so existing bakes stay valid.
      let panToken = track.pan == 0 ? "" : "|pan\(track.pan)"
      parts.append(
        "track|\(track.id.uuidString)|\(mediaPath)|\(modToken)|\(groupID)|\(track.volume)|\(track.isMuted)|\(track.isSolo)|\(track.trimStartSeconds)|\(trimEnd)|\(track.excludeFromTranspose)\(panToken)"
      )
    }

    let joined = parts.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(joined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  static func sourceModificationDates(for song: Song) -> [UUID: Date] {
    let inputs = SongTrackLoader.trackInputs(for: song)
    return SongTrackLoader.sourceModificationDates(for: inputs)
  }

  private static func fingerprint(tempoChanges: [TempoChange]) -> String {
    tempoChanges
      .sorted { $0.startMeasure < $1.startMeasure }
      .map { "\($0.startMeasure):\($0.bpm)" }
      .joined(separator: ",")
  }

  private static func fingerprint(timeSignatures: [TimeSignatureChange]) -> String {
    timeSignatures
      .sorted { $0.startMeasure < $1.startMeasure }
      .map { "\($0.startMeasure):\($0.numerator)/\($0.denominator)" }
      .joined(separator: ",")
  }

  private static func fingerprint(midiEvents: [MIDIEvent]) -> String {
    midiEvents
      .sorted { $0.timelineSeconds < $1.timelineSeconds }
      .map { "\($0.timelineSeconds)|\($0.trackID.uuidString)|\($0.commandID.uuidString)|\($0.label)" }
      .joined(separator: ";")
  }

  /// Only what changes rendered audio: clip placement and the song length markers can extend.
  private static func fingerprint(timeline: SongTimeline) -> String {
    let clipPart = timeline.clips
      .sorted {
        $0.trackID == $1.trackID
          ? $0.timelineStartSeconds < $1.timelineStartSeconds
          : $0.trackID.uuidString < $1.trackID.uuidString
      }
      .map { "\($0.trackID.uuidString)|\($0.timelineStartSeconds)|\($0.duration)|\($0.sourceStartSeconds)" }
      .joined(separator: ";")
    return "clips=\(clipPart)||duration=\(timeline.duration)"
  }
}
