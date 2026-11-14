import Foundation

extension ClipEditing {
    /// The fade a drag of `edge`'s fade handle to `time` gives: it runs from that end of the clip
    /// to `time`, clamped inside the clip. A new fade is an S-curve; an existing one keeps its
    /// shape and bend.
    static func fade(_ clip: TrackClip, edge: Edge, draggedTo time: TimeInterval) -> ClipFade {
        let inside = min(max(time, clip.timelineStartSeconds), clip.timelineEndSeconds)
        switch edge {
        case .leading:
            return clip.fadeIn.with(duration: inside - clip.timelineStartSeconds)
        case .trailing:
            return clip.fadeOut.with(duration: clip.timelineEndSeconds - inside)
        }
    }

    /// Replaces the fade at one end of a clip. The clip keeps it no longer than itself.
    static func setFade(_ fade: ClipFade, edge: Edge, clipID: UUID, in clips: inout [TrackClip]) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        switch edge {
        case .leading: clips[index].fadeIn = fade
        case .trailing: clips[index].fadeOut = fade
        }
    }

    /// Gives every existing fade on the listed clips the same shape, with no bend.
    static func setFadeShape(_ shape: ClipFadeShape, clipIDs: Set<UUID>, in clips: inout [TrackClip]) {
        for index in clips.indices where clipIDs.contains(clips[index].id) {
            clips[index].fadeIn = clips[index].fadeIn.with(shape: shape).with(curvature: 0)
            clips[index].fadeOut = clips[index].fadeOut.with(shape: shape).with(curvature: 0)
        }
    }

    static func removeFades(clipIDs: Set<UUID>, in clips: inout [TrackClip]) {
        for index in clips.indices where clipIDs.contains(clips[index].id) {
            clips[index].fadeIn = .none
            clips[index].fadeOut = .none
        }
    }
}
