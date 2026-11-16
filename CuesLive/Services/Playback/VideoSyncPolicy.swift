import Foundation

/// What the video player should do to match the audio transport on one sync tick.
enum VideoSyncAction: Equatable {
    case none
    /// The playhead is outside the movie: stop and show black.
    case hide
    /// Run at normal speed from this movie time, starting now.
    case play(from: TimeInterval)
    /// Stop on this movie time.
    case pause(at: TimeInterval)
    /// Show the frame at this movie time while stopped.
    case seek(to: TimeInterval)
}

/// Decides how to keep the picture locked to the audio. Audio is the master clock: the player
/// is only ever moved to meet it, never the other way round.
enum VideoSyncPolicy {
    /// Drift allowed while playing before the player is re-locked. Just over a frame at 25 fps.
    static let playingTolerance: TimeInterval = 0.045
    /// Drift allowed while stopped, so scrubbing shows the frame under the playhead.
    static let pausedTolerance: TimeInterval = 0.01
    /// After a re-lock the decoder needs a moment to reach the new time; drift is ignored meanwhile.
    static let settleInterval: TimeInterval = 0.5

    struct PlayerState: Equatable {
        var seconds: TimeInterval
        var isRunning: Bool
        var isSeeking: Bool
        var secondsSinceLastLock: TimeInterval
    }

    /// - Parameters:
    ///   - target: Movie time under the audio playhead, nil when the playhead is outside the movie.
    ///   - isTransportPlaying: Whether the audio is playing.
    static func action(
        target: TimeInterval?,
        isTransportPlaying: Bool,
        player: PlayerState
    ) -> VideoSyncAction {
        guard let target else { return .hide }
        let drift = abs(player.seconds - target)

        if isTransportPlaying {
            guard player.isRunning else { return .play(from: target) }
            guard player.secondsSinceLastLock >= settleInterval else { return .none }
            return drift > playingTolerance ? .play(from: target) : .none
        }

        if player.isRunning {
            return .pause(at: target)
        }
        guard !player.isSeeking else { return .none }
        return drift > pausedTolerance ? .seek(to: target) : .none
    }
}
