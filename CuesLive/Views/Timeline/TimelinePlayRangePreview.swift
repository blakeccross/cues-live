import Foundation
import Observation

/// The in and out points while a flag is being dragged. Only the flags and the lane shade read
/// it, so a drag tick redraws them without rebuilding the editor.
@MainActor
@Observable
final class TimelinePlayRangePreview {
    var range: ClosedRange<TimeInterval>?
}
