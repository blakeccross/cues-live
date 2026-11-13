import SwiftUI

struct MappableLiveControlModifier: ViewModifier {
    let action: MappableLiveAction
    var cornerRadius: CGFloat = AppRadius.sm
    /// When false the control gets no outline or idle tint in mapping mode, only a fill
    /// while it is the pending control. Used for compact transport buttons.
    var isOutlined: Bool = true

    @Environment(InputMappingController.self) private var mapping

    func body(content: Content) -> some View {
        let isHighlighted = mapping.showsLiveHighlights
        let isPending = isHighlighted && mapping.pendingAction == action
        let assignmentLabel = assignmentBadgeLabel
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        // An overlay (not a ZStack wrapper) keeps `content` as the view's identity, so a List row
        // still gets its own row background and sizing.
        content
            .allowsHitTesting(!isHighlighted)
            .overlay {
                if isHighlighted {
                    ZStack {
                        shape
                            .fill(AppColors.accent.opacity(isPending ? 0.22 : (isOutlined ? 0.08 : 0)))
                            .overlay {
                                if isOutlined {
                                    shape.strokeBorder(AppColors.accent, lineWidth: isPending ? 3 : 2)
                                }
                            }
                            .allowsHitTesting(false)

                        Color.clear
                            .contentShape(shape)
                            .onTapGesture {
                                mapping.selectAction(action)
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(accessibilityLabel(assignment: assignmentLabel))

                        if let assignmentLabel {
                            MappingAssignmentBadge(title: assignmentLabel)
                                .padding(AppSpacing.xxs)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .animation(AppAnimation.fadeQuick, value: isHighlighted)
            .animation(AppAnimation.fadeQuick, value: isPending)
            .animation(AppAnimation.fadeQuick, value: assignmentLabel)
    }

    private var assignmentBadgeLabel: String? {
        guard mapping.showsLiveHighlights else { return nil }
        return mapping.liveAssignmentBadge(for: action)
    }

    private func accessibilityLabel(assignment: String?) -> String {
        if let assignment {
            return "Map \(action.title), assigned to \(assignment)"
        }
        return "Map \(action.title)"
    }
}

private struct MappingAssignmentBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.82), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .fixedSize()
    }
}

extension View {
    func mappableLiveControl(
        _ action: MappableLiveAction,
        cornerRadius: CGFloat = AppRadius.sm,
        isOutlined: Bool = true
    ) -> some View {
        modifier(
            MappableLiveControlModifier(
                action: action,
                cornerRadius: cornerRadius,
                isOutlined: isOutlined
            )
        )
    }
}
