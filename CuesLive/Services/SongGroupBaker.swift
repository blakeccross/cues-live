import AVFoundation
import Foundation
import SwiftData

enum SongGroupBaker {
  enum BakeError: LocalizedError {
    case missingProjectFile
    case noTracks
    case renderFailed(String)

    var errorDescription: String? {
      switch self {
      case .missingProjectFile:
        return "This song does not have a project file."
      case .noTracks:
        return "This song has no tracks to bake."
      case .renderFailed(let detail):
        return "Could not bake group stems: \(detail)"
      }
    }
  }

  struct Progress: Sendable {
    var phase: String
    var completedGroups: Int
    var totalGroups: Int
  }

  struct BakePlan {
    struct Group {
      let groupID: UUID?
      let tracks: [AudioTrack]
    }

    let groups: [Group]
    let timelineDuration: TimeInterval
    let sectionsByTrack: [UUID: [ArrangementDisplaySection]]
    let masterSections: [ArrangementDisplaySection]
    let fingerprint: String
  }

  static func makePlan(for song: Song) throws -> BakePlan {
    guard SongProjectBridge.projectURL(for: song) != nil else {
      throw BakeError.missingProjectFile
    }

    let tracks = song.sortedTracks
    guard !tracks.isEmpty else {
      throw BakeError.noTracks
    }

    let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
    let arrangement = SongPlaybackArrangementLoader.sections(for: song)
    let timelineDuration = SongArrangementStore.effectiveTimelineDuration(
      rulerSections: arrangement.masterSections,
      trackSections: arrangement.sectionsByTrack
    )

    var grouped: [UUID?: [AudioTrack]] = [:]
    for track in tracks {
      grouped[track.group?.id, default: []].append(track)
    }

    let groups = grouped.keys.sorted { lhs, rhs in
      switch (lhs, rhs) {
      case (nil, nil):
        return false
      case (nil, _):
        return false
      case (_, nil):
        return true
      case let (left?, right?):
        return left.uuidString < right.uuidString
      }
    }.map { groupID in
      BakePlan.Group(
        groupID: groupID,
        tracks: grouped[groupID] ?? []
      )
    }

    let fingerprint = SongBakeFingerprint.compute(
      for: song,
      projectState: projectState,
      trackModificationDates: SongBakeFingerprint.sourceModificationDates(for: song)
    )

    return BakePlan(
      groups: groups,
      timelineDuration: timelineDuration,
      sectionsByTrack: arrangement.sectionsByTrack,
      masterSections: arrangement.masterSections,
      fingerprint: fingerprint
    )
  }

  static func bake(
    song: Song,
    context: ModelContext,
    onProgress: (@Sendable (Progress) -> Void)? = nil
  ) async throws -> SongBakeManifest {
    let plan = try makePlan(for: song)
    guard let bakedDirectory = SongBakeStore.bakedDirectory(for: song),
          let groupsDirectory = SongBakeStore.bakedGroupsDirectory(for: song) else {
      throw BakeError.missingProjectFile
    }

    try? FileManager.default.removeItem(at: bakedDirectory)
    try FileManager.default.createDirectory(at: groupsDirectory, withIntermediateDirectories: true)

    var groupStems: [BakedGroupStem] = []
    let totalGroups = plan.groups.count

    for (index, group) in plan.groups.enumerated() {
      onProgress?(
        Progress(
          phase: groupTitle(for: group),
          completedGroups: index,
          totalGroups: totalGroups
        )
      )

      let audibleTracks = audibleBakeTracks(from: group.tracks)
      guard !audibleTracks.isEmpty else { continue }

      let rendered = try await renderGroupStem(
        song: song,
        tracks: audibleTracks,
        timelineDuration: plan.timelineDuration,
        sectionsByTrack: plan.sectionsByTrack,
        masterSections: plan.masterSections
      )

      let groupKey = group.groupID ?? OutputRoutingStore.ungroupedRouteID
      let fileName = "\(groupKey.uuidString).caf"
      let relativePath = "Baked/groups/\(fileName)"
      guard let outputURL = SongBakeStore.bakedStemURL(for: song, relativePath: relativePath) else {
        throw BakeError.missingProjectFile
      }

      try StemAudioWriter.writeCAF(buffer: rendered, to: outputURL)

      groupStems.append(
        BakedGroupStem(
          playbackTrackID: SongBakeStore.bakedGroupTrackID(songID: song.id, groupID: group.groupID),
          groupID: group.groupID,
          relativePath: relativePath,
          duration: Double(rendered.frameCount) / rendered.sampleRate,
          trackIDs: audibleTracks.map(\.id)
        )
      )
    }

    let manifest = SongBakeManifest(
      bakedAt: Date(),
      fingerprint: plan.fingerprint,
      groupStems: groupStems
    )

    try SongBakeStore.saveManifest(manifest, for: song)
    onProgress?(
      Progress(
        phase: "Done",
        completedGroups: totalGroups,
        totalGroups: totalGroups
      )
    )
    return manifest
  }

  private static func groupTitle(for group: BakePlan.Group) -> String {
    if let track = group.tracks.first, let trackGroup = track.group {
      return trackGroup.name
    }
    return "Ungrouped"
  }

  private static func audibleBakeTracks(from tracks: [AudioTrack]) -> [AudioTrack] {
    let anySolo = tracks.contains { $0.isSolo }
    return tracks.filter { track in
      if track.isMuted { return false }
      if anySolo, !track.isSolo { return false }
      if track.volume <= 0.0001 { return false }
      return true
    }
  }

  private static func renderGroupStem(
    song: Song,
    tracks: [AudioTrack],
    timelineDuration: TimeInterval,
    sectionsByTrack: [UUID: [ArrangementDisplaySection]],
    masterSections: [ArrangementDisplaySection]
  ) async throws -> DecodedStemBuffer {
    try await Task.detached(priority: .userInitiated) {
      let frameCount = max(1, Int((timelineDuration * DecodedStemBuffer.engineSampleRate).rounded(.up)))
      let output = try DecodedStemBuffer.silent(
        frameCount: frameCount,
        sampleRate: DecodedStemBuffer.engineSampleRate,
        channelCount: 2
      )

      let usesArrangement = !masterSections.isEmpty

      for track in tracks {
        guard let sourceURL = FileStore.trackURL(for: song, track: track) else { continue }

        var settings = AudioEngineManager.TrackSettings(track: track)
        var sourceBuffer = try DecodedStemBuffer.decode(from: sourceURL)
        let fileDuration = Double(sourceBuffer.frameCount) / sourceBuffer.sampleRate
        if settings.trimEnd == nil {
          settings.trimEnd = fileDuration
        }

        if song.transposeHighQuality,
           Int((settings.pitchCents / 100).rounded()) != 0 {
          sourceBuffer = try AudioEngineManager.pitchShiftedBuffer(
            from: sourceBuffer,
            settings: settings
          )
          settings.pitchCents = 0
        }

        let sections = sectionsByTrack[track.id] ?? []
        let trackUsesArrangement = usesArrangement || !sections.isEmpty
        let mapper = ArrangementTimelineMapper(
          sections: sections,
          trimStart: settings.trimStart,
          trimEnd: settings.trimEnd ?? fileDuration,
          usesArrangement: trackUsesArrangement
        )

        let gain = Float(track.volume)
        GroupStemOfflineRenderer.mix(
          source: sourceBuffer,
          into: output,
          mapper: mapper,
          gain: gain
        )
      }

      return output
    }.value
  }

}

enum GroupStemOfflineRenderer {
  static func mix(
    source: DecodedStemBuffer,
    into output: DecodedStemBuffer,
    mapper: ArrangementTimelineMapper,
    gain: Float
  ) {
    guard gain > 0, source.frameCount > 0, output.frameCount > 0 else { return }

    let sampleRate = output.sampleRate
    var masterTime: TimeInterval = 0
    var renderedFrames = 0
    let totalFrames = output.frameCount

    while renderedFrames < totalFrames {
      let bufferRemaining = Double(totalFrames - renderedFrames) / sampleRate
      let regionSeconds = mapper.regionRemainingSeconds(
        fromMasterTimeline: masterTime,
        bufferLimit: bufferRemaining
      )
      guard regionSeconds > 0 else { break }

      guard let sourceStart = mapper.sourceSeconds(atMasterTimeline: masterTime) else {
        let skipFrames = min(
          totalFrames - renderedFrames,
          Int((regionSeconds * sampleRate).rounded(.down))
        )
        guard skipFrames > 0 else { break }
        renderedFrames += skipFrames
        masterTime += Double(skipFrames) / sampleRate
        continue
      }

      let runFrames = min(
        totalFrames - renderedFrames,
        Int((regionSeconds * sampleRate).rounded(.down))
      )
      guard runFrames > 0 else { break }

      let sourceFrame = Int((sourceStart * sampleRate).rounded(.toNearestOrAwayFromZero))
      mixChunk(
        source: source,
        sourceFrame: sourceFrame,
        frameCount: runFrames,
        into: output,
        destinationFrame: renderedFrames,
        gain: gain
      )

      renderedFrames += runFrames
      masterTime += Double(runFrames) / sampleRate
    }
  }

  private static func mixChunk(
    source: DecodedStemBuffer,
    sourceFrame: Int,
    frameCount: Int,
    into output: DecodedStemBuffer,
    destinationFrame: Int,
    gain: Float
  ) {
    guard frameCount > 0 else { return }

    if source.channelCount == 1 {
      mixChannel(
        source: source,
        sourceChannel: 0,
        sourceFrame: sourceFrame,
        frameCount: frameCount,
        into: output,
        destinationChannel: 0,
        destinationFrame: destinationFrame,
        gain: gain
      )
      if output.channelCount >= 2 {
        mixChannel(
          source: source,
          sourceChannel: 0,
          sourceFrame: sourceFrame,
          frameCount: frameCount,
          into: output,
          destinationChannel: 1,
          destinationFrame: destinationFrame,
          gain: gain
        )
      }
      return
    }

    let channelsToMix = min(source.channelCount, output.channelCount)
    for channel in 0..<channelsToMix {
      mixChannel(
        source: source,
        sourceChannel: channel,
        sourceFrame: sourceFrame,
        frameCount: frameCount,
        into: output,
        destinationChannel: channel,
        destinationFrame: destinationFrame,
        gain: gain
      )
    }
  }

  private static func mixChannel(
    source: DecodedStemBuffer,
    sourceChannel: Int,
    sourceFrame: Int,
    frameCount: Int,
    into output: DecodedStemBuffer,
    destinationChannel: Int,
    destinationFrame: Int,
    gain: Float
  ) {
    guard sourceFrame >= 0, destinationFrame >= 0 else { return }

    let available = min(
      frameCount,
      source.frameCount - sourceFrame,
      output.frameCount - destinationFrame
    )
    guard available > 0 else { return }

    let sourcePointer = source.channelPointer(sourceChannel).advanced(by: sourceFrame)
    let destination = output.mutableChannelPointer(destinationChannel).advanced(by: destinationFrame)

    if gain == 1 {
      for index in 0..<available {
        destination[index] += sourcePointer[index]
      }
    } else {
      for index in 0..<available {
        destination[index] += sourcePointer[index] * gain
      }
    }
  }
}
