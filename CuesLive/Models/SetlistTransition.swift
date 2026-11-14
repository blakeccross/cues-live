import Foundation

enum SetlistTransition: String, CaseIterable, Identifiable {
    case `continue`
    case stop
    case overlap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .continue:
            return "Continue"
        case .stop:
            return "Stop"
        case .overlap:
            return "Overlap"
        }
    }

    var systemImage: String {
        switch self {
        case .continue:
            return "arrow.right"
        case .stop:
            return "stop"
        case .overlap:
            return "arrow.triangle.merge"
        }
    }

    var requiresOverlapConfig: Bool {
        self == .overlap
    }
}
