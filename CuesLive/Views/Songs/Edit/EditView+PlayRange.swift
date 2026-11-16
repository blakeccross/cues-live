import SwiftUI

extension EditView {
    /// Commits a dragged in or out flag. The drag has already snapped the time to a beat;
    /// only the range changes, never audio.
    func movePlayRange(to range: SongPlayRange) {
        guard range != timeline.playRange else { return }
        let movesIn = range.startSeconds != timeline.playRange.startSeconds
        commitTimelineEdit(movesIn ? "Move In Point" : "Move Out Point") { timeline in
            timeline.playRange = range
        }
    }

    /// Plays the whole song again: the in point returns to zero and the out point follows the content.
    func resetPlayRange() {
        guard timeline.playRange != SongPlayRange() else { return }
        commitTimelineEdit("Reset In and Out Points") { timeline in
            timeline.playRange = SongPlayRange()
        }
    }
}
