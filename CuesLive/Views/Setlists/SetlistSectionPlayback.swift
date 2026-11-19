import Foundation

/// Playhead and cue state for the expanded section lists, plus how to act on a tapped section.
struct SetlistSectionPlayback {
    var playheadTime: () -> TimeInterval
    var isPlaying: Bool
    /// The clock time while stopped, so seeks redraw the progress without a running timeline.
    var idlePlayheadTime: TimeInterval?
    var cuedSectionID: UUID?
    var cueFlashPhase: Bool
    /// Cues the section in the current song, or jumps to it in another song.
    var selectSection: (_ playbackIndex: Int, _ section: SongSection) -> Void
}
