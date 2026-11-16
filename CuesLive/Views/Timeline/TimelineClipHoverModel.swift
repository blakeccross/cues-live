import Foundation
import Observation

/// A view drawn outside SwiftUI that marks the clip under the pointer.
@MainActor
protocol TimelineClipHoverFollowing: AnyObject {
    func hoveredClipDidChange(_ clipID: UUID?)
}

/// The clip under the pointer, which shows its fade curves and knobs.
///
/// Scrolling slides clips under a still pointer, so this changes many times a second. It lives
/// outside the editor's state so a change redraws the fade knobs and the lane canvas only,
/// instead of rebuilding the editor and every lane.
@MainActor
@Observable
final class TimelineClipHoverModel {
    private(set) var clipID: UUID?
    /// Told about every change directly, outside SwiftUI's update cycle.
    @ObservationIgnored weak var laneCanvas: (any TimelineClipHoverFollowing)?

    func setClipID(_ newClipID: UUID?) {
        guard clipID != newClipID else { return }
        clipID = newClipID
        laneCanvas?.hoveredClipDidChange(newClipID)
    }
}
