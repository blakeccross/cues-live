 import Foundation
import SwiftData

@Model
final class AudioTrack {
    var id: UUID
    var displayName: String
    var relativeFilePath: String
    var mediaPath: String?
    var mediaPathStyleRaw: String?
    var mediaBookmarkData: Data?
    var sortOrder: Int
    var volume: Double
    var isMuted: Bool
    var isSolo: Bool
    var trimStartSeconds: Double
    var trimEndSeconds: Double?
    var excludeFromTranspose: Bool

    var mediaPathStyle: MediaPathStyle? {
        get {
            guard let mediaPathStyleRaw else { return nil }
            return MediaPathStyle(rawValue: mediaPathStyleRaw)
        }
        set {
            mediaPathStyleRaw = newValue?.rawValue
        }
    }

    var song: Song?
    var group: TrackGroup?

    init(displayName: String, relativeFilePath: String, sortOrder: Int) {
        id = UUID()
        self.displayName = displayName
        self.relativeFilePath = relativeFilePath
        self.sortOrder = sortOrder
        volume = 1.0
        isMuted = false
        isSolo = false
        trimStartSeconds = 0.0
        trimEndSeconds = nil
        excludeFromTranspose = false
        mediaPath = nil
        mediaPathStyleRaw = nil
        mediaBookmarkData = nil
    }
}
