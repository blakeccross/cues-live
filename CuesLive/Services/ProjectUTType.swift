import Foundation
import UniformTypeIdentifiers

enum ProjectUTType {
    static let songProjectExtension = "cueslive"
    static let showProjectExtension = "cueshow"
    /// Opaque package extension; new exports are plain folders.
    static let setlistPackageExtension = "cueset"

    static let songProjectIdentifier = "live.cues.song"
    static let showProjectIdentifier = "live.cues.show"

    static var songProjectType: UTType {
        UTType(exportedAs: songProjectIdentifier, conformingTo: .json)
    }

    static var showProjectType: UTType {
        UTType(exportedAs: showProjectIdentifier, conformingTo: .json)
    }
}
