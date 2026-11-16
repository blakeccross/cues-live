import SwiftUI

extension SetlistTransition {
    /// Glyph tint for this transition in setlist rows.
    var badgeColor: Color {
        switch self {
        case .continue:
            return AppColors.textSecondary
        case .stop:
            return AppColors.muteActive
        case .overlap:
            return AppColors.transitionOverlap
        }
    }
}
