import SwiftUI

extension EditView {
    /// Ends a drag of a fade handle: the fade at that end of the clip becomes `fade`.
    func commitFade(_ fade: ClipFade, edge: ClipEditing.Edge, clipID: UUID) {
        commitFadeEdit(edge == .leading ? "Fade In" : "Fade Out") { clips in
            ClipEditing.setFade(fade, edge: edge, clipID: clipID, in: &clips)
        }
    }

    func setSelectedFadeShape(_ shape: ClipFadeShape) {
        let ids = clipSelection.clipIDs
        commitFadeEdit("Change Fade Shape") { clips in
            ClipEditing.setFadeShape(shape, clipIDs: ids, in: &clips)
        }
    }

    func removeSelectedFades() {
        let ids = clipSelection.clipIDs
        commitFadeEdit("Remove Fades") { clips in
            ClipEditing.removeFades(clipIDs: ids, in: &clips)
        }
    }

    /// Commits `edit` as one undo step, or nothing when it leaves every clip as it was.
    private func commitFadeEdit(_ actionName: String, _ edit: (inout [TrackClip]) -> Void) {
        var edited = timeline.clips
        edit(&edited)
        guard edited != timeline.clips else { return }
        commitTimelineEdit(actionName) { timeline in
            timeline.clips = edited
        }
    }
}
