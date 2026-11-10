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
    /// -1 (hard left) … +1 (hard right); the UI shows this as -50…50.
    var pan: Double = 0
    var isMuted: Bool
    var isSolo: Bool
    var trimStartSeconds: Double
    var trimEndSeconds: Double?
    /// When false, a song key change leaves this stem at its original pitch.
    var includeInKeyChange: Bool = true
    /// Length of the source file the last time it was readable, so layout survives missing media.
    var sourceDurationSeconds: Double?

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
        pan = 0
        isMuted = false
        isSolo = false
        trimStartSeconds = 0.0
        trimEndSeconds = nil
        includeInKeyChange = true
        sourceDurationSeconds = nil
        mediaPath = nil
        mediaPathStyleRaw = nil
        mediaBookmarkData = nil
    }
}
