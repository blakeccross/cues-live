import Foundation
import SwiftData

@Model
final class GroupOutputRoute {
    var groupID: UUID
    /// Output device these assignments belong to. Empty means a route saved
    /// before devices were remembered; it is claimed by the selected device.
    var deviceUID: String = ""
    var destinationKind: String
    var destinationChannel: Int

    init(groupID: UUID, deviceUID: String = "", destination: OutputDestination) {
        self.groupID = groupID
        self.deviceUID = deviceUID
        switch destination {
        case .stereoPair(let startChannel):
            destinationKind = "stereo"
            destinationChannel = startChannel
        case .mono(let channel):
            destinationKind = "mono"
            destinationChannel = channel
        }
    }

    var destination: OutputDestination {
        get {
            if destinationKind == "mono" {
                return .mono(channel: destinationChannel)
            }
            return .stereoPair(startChannel: destinationChannel)
        }
        set {
            switch newValue {
            case .stereoPair(let startChannel):
                destinationKind = "stereo"
                destinationChannel = startChannel
            case .mono(let channel):
                destinationKind = "mono"
                destinationChannel = channel
            }
        }
    }
}
