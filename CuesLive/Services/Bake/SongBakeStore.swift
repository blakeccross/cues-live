import Foundation
import SwiftData

enum SongBakeStatus: Sendable {
  case none
  case stale
  case current
}

enum SongBakeStore {
  enum BakeError: LocalizedError {
    case missingProjectFile
    case missingBakedFile(String)

    var errorDescription: String? {
      switch self {
      case .missingProjectFile:
        return "This song does not have a project file."
      case .missingBakedFile(let path):
        return "Missing baked stem at \(path)."
      }
    }
  }

  static func bakedDirectory(for song: Song) -> URL? {
    guard let projectURL = SongProjectBridge.projectURL(for: song) else { return nil }
    return projectURL
      .deletingLastPathComponent()
      .appendingPathComponent("Baked", isDirectory: true)
  }

  static func bakedGroupsDirectory(for song: Song) -> URL? {
    bakedDirectory(for: song)?
      .appendingPathComponent("groups", isDirectory: true)
  }

  static func manifest(for song: Song) -> SongBakeManifest? {
    guard let projectURL = SongProjectBridge.projectURL(for: song),
          let document = try? ProjectFileStore.load(from: projectURL) else {
      return nil
    }
    return document.bakeManifest
  }

  static func status(for song: Song) -> SongBakeStatus {
    guard let manifest = manifest(for: song), !manifest.isEmpty else {
      return .none
    }

    let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
    let fingerprint = SongBakeFingerprint.compute(
      for: song,
      projectState: projectState,
      trackModificationDates: SongBakeFingerprint.sourceModificationDates(for: song)
    )

    guard manifest.fingerprint == fingerprint else {
      return .stale
    }

    guard bakedFilesExist(for: song, manifest: manifest) else {
      return .stale
    }

    return .current
  }

  static func hasValidBake(for song: Song) -> Bool {
    status(for: song) == .current
  }

  static func needsBake(for song: Song) -> Bool {
    guard song.sortedTracks.count >= SongBakeFingerprint.performanceTrackThreshold else {
      return false
    }
    return status(for: song) != .current
  }

  static func bakedStemURL(for song: Song, relativePath: String) -> URL? {
    guard let projectURL = SongProjectBridge.projectURL(for: song) else { return nil }
    return projectURL.deletingLastPathComponent().appendingPathComponent(relativePath)
  }

  static func bakedGroupTrackID(songID: UUID, groupID: UUID?) -> UUID {
    let groupKey = groupID ?? OutputRoutingStore.ungroupedRouteID
    var bytes = songID.uuid
    let groupBytes = groupKey.uuid
    bytes.0 ^= groupBytes.0
    bytes.1 ^= groupBytes.1
    bytes.2 ^= groupBytes.2
    bytes.3 ^= groupBytes.3
    bytes.4 ^= groupBytes.4
    bytes.5 ^= groupBytes.5
    bytes.6 ^= groupBytes.6
    bytes.7 = 0xBA
    bytes.8 = (bytes.8 & 0x3F) | 0x80
    return UUID(uuid: bytes)
  }

  @discardableResult
  static func saveManifest(_ manifest: SongBakeManifest, for song: Song) throws -> URL {
    guard let projectURL = SongProjectBridge.projectURL(for: song) else {
      throw BakeError.missingProjectFile
    }

    var document = try ProjectFileStore.load(from: projectURL)
    document.bakeManifest = manifest.isEmpty ? nil : manifest
    try ProjectFileStore.save(document, to: projectURL)
    return projectURL
  }

  static func invalidateBake(for song: Song) throws {
    guard let projectURL = SongProjectBridge.projectURL(for: song) else { return }

    var document = try ProjectFileStore.load(from: projectURL)
    document.bakeManifest = nil
    try ProjectFileStore.save(document, to: projectURL)
    deleteBakedFiles(for: song)
  }

  static func deleteBakedFiles(for song: Song) {
    guard let bakedDirectory = bakedDirectory(for: song) else { return }
    try? FileManager.default.removeItem(at: bakedDirectory)
  }

  static func syncValidityOnPersist(for song: Song) throws {
    guard let projectURL = SongProjectBridge.projectURL(for: song) else { return }
    guard var document = try? ProjectFileStore.load(from: projectURL),
          let manifest = document.bakeManifest else {
      return
    }

    let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
    let fingerprint = SongBakeFingerprint.compute(
      for: song,
      projectState: projectState,
      trackModificationDates: SongBakeFingerprint.sourceModificationDates(for: song)
    )

    if manifest.fingerprint != fingerprint || !bakedFilesExist(for: song, manifest: manifest) {
      document.bakeManifest = nil
      try ProjectFileStore.save(document, to: projectURL)
      deleteBakedFiles(for: song)
    }
  }

  private static func bakedFilesExist(for song: Song, manifest: SongBakeManifest) -> Bool {
    for stem in manifest.groupStems {
      guard let url = bakedStemURL(for: song, relativePath: stem.relativePath),
            FileManager.default.fileExists(atPath: url.path) else {
        return false
      }
    }

    return true
  }
}
