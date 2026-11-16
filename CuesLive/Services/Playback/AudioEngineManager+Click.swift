import Foundation

extension AudioEngineManager {
    /// The generated click loaded with the current song, when there is one.
    var loadedClick: (source: ProceduralClickSource, settings: TrackSettings)? {
        guard let track = tracks[ClickPlaybackSupport.payloadID],
              let source = track.memoryPlayer.sampleSource as? ProceduralClickSource else {
            return nil
        }
        return (source, track.settings)
    }
}
