import Foundation
import Observation

/// A view drawn outside SwiftUI that shades the lanes outside the in and out points.
@MainActor
protocol TimelinePlayRangeFollowing: AnyObject {
    func playRangePreviewDidChange(_ range: ClosedRange<TimeInterval>?)
}

/// The in and out points while a flag is being dragged. Only the flags read it in SwiftUI, and
/// the lane shade is told directly, so a drag tick redraws them without rebuilding the editor.
@MainActor
@Observable
final class TimelinePlayRangePreview {
    private(set) var range: ClosedRange<TimeInterval>?
    /// Told about every change directly, outside SwiftUI's update cycle.
    @ObservationIgnored weak var laneShade: (any TimelinePlayRangeFollowing)?

    func setRange(_ newRange: ClosedRange<TimeInterval>?) {
        guard range != newRange else { return }
        range = newRange
        laneShade?.playRangePreviewDidChange(newRange)
    }
}
