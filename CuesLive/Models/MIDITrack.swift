import Foundation
import SwiftData

/// Sends commands from its associated `MIDIDevice` to external gear at manually-placed
/// points on the song timeline. Event data is stored in the song project file.
@Model
final class MIDITrack {
    var id: UUID
    var displayName: String
    var sortOrder: Int

    var device: MIDIDevice?
    var song: Song?
    /// Lane height in points. Missing or out-of-range values display at the default.
    var laneHeight: Double = TrackLaneHeight.storedDefault

    init(displayName: String, sortOrder: Int) {
        id = UUID()
        self.displayName = displayName
        self.sortOrder = sortOrder
    }
}
