import Foundation

enum PlaybackCoordinatorError: LocalizedError {
    case noTracks

    var errorDescription: String? {
        switch self {
        case .noTracks:
            return "This song has no imported tracks."
        }
    }
}
