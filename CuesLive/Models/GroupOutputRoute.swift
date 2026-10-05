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
        case .none:
            destinationKind = "none"
            destinationChannel = 0
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
            switch destinationKind {
            case "mono":
                return .mono(channel: destinationChannel)
            case "none":
                return .none
            default:
                return .stereoPair(startChannel: destinationChannel)
            }
        }
        set {
            switch newValue {
            case .none:
                destinationKind = "none"
                destinationChannel = 0
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
