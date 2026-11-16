import Foundation

extension AudioEngineManager {
    /// The song's in point. Stopping rewinds here.
    var startTime: TimeInterval { playbackLayout?.startTime ?? 0 }
}
