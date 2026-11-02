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
  parts.append("arrangement|\(fingerprint(arrangement: projectState.arrangement, markers: projectState.markers))")

    let sortedTracks = song.sortedTracks.sorted { $0.sortOrder < $1.sortOrder }
    for track in sortedTracks {
      let modDate = trackModificationDates[track.id] ?? .distantPast
      let modToken = Int(modDate.timeIntervalSince1970)
      let mediaPath = track.mediaPath ?? track.relativeFilePath
      let groupID = track.group?.id.uuidString ?? "ungrouped"
      let trimEnd = track.trimEndSeconds.map { String($0) } ?? "nil"
      parts.append(
        "track|\(track.id.uuidString)|\(mediaPath)|\(modToken)|\(groupID)|\(track.volume)|\(track.isMuted)|\(track.isSolo)|\(track.trimStartSeconds)|\(trimEnd)|\(track.excludeFromTranspose)"
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

  private static func fingerprint(
    arrangement: SongArrangement,
    markers: [ArrangementMarker]
  ) -> String {
    let markerPart = markers
      .sorted { $0.startSeconds < $1.startSeconds }
      .map { "\($0.id.uuidString)|\($0.name)|\($0.startSeconds)" }
      .joined(separator: ";")

    let slotPart = arrangement.slots
      .map { "\($0.id.uuidString)|\($0.markerID.uuidString)" }
      .joined(separator: ";")

    let trimPart = arrangement.clipTrims
      .map { "\($0.slotID.uuidString)|\($0.trackID.uuidString)|\($0.leadingTrim)|\($0.trailingTrim)" }
      .joined(separator: ";")

    let regionPart = arrangement.clipRegions
      .map { "\($0.id.uuidString)|\($0.trackID.uuidString)|\($0.timelineStartSeconds)|\($0.timelineEndSeconds)" }
      .joined(separator: ";")

    let removedPart = arrangement.removedClips
      .map { "\($0.slotID.uuidString)" }
      .joined(separator: ",")

    let loopPart = arrangement.loopSlotIDs
      .map(\.uuidString)
      .sorted()
      .joined(separator: ",")

    return "markers=\(markerPart)||slots=\(slotPart)||trims=\(trimPart)||regions=\(regionPart)||removed=\(removedPart)||loops=\(loopPart)"
  }
}
