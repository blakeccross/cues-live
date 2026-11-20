import Foundation
import SwiftData

@Model
final class OutputRoutingConfig {
    var id: UUID
    var selectedDeviceUID: String?
    var ungroupedVolume: Double = 1.0
    var ungroupedIsMuted: Bool = false
    var ungroupedIsSoloed: Bool = false

    init(
        selectedDeviceUID: String? = nil,
        ungroupedVolume: Double = 1.0,
        ungroupedIsMuted: Bool = false
    ) {
        id = UUID()
        self.selectedDeviceUID = selectedDeviceUID
        self.ungroupedVolume = ungroupedVolume
        self.ungroupedIsMuted = ungroupedIsMuted
    }
}
