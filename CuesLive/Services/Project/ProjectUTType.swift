import Foundation
import UniformTypeIdentifiers

enum ProjectUTType {
    static let songProjectExtension = "cueslive"
    static let showProjectExtension = "cueshow"

    static let songProjectIdentifier = "live.cues.song"
    static let showProjectIdentifier = "live.cues.show"

    static var showProjectType: UTType {
        UTType(exportedAs: showProjectIdentifier, conformingTo: .json)
    }
}
