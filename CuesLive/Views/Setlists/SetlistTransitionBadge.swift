import SwiftUI

extension SetlistTransition {
    /// Ring and glyph tint for this transition in setlist rows and badges.
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

/// Circular badge showing how a setlist song hands off to the next one.
struct SetlistTransitionBadge: View {
    let transition: SetlistTransition
    var size: CGFloat = 28
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                badgeContent
            }
            .buttonStyle(.plain)
            .appLinkPointer()
        } else {
            badgeContent
        }
    }

    private var badgeContent: some View {
        Image(systemName: transition.systemImage)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: size, height: size)
            .background(AppColors.surfaceElevated)
            .overlay {
                Circle()
                    .stroke(transition.badgeColor, lineWidth: 1.5)
            }
            .clipShape(Circle())
    }
}
