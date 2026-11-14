import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Hairline between two panes that resizes one of them when dragged.
///
/// `edge` is the side of the resized pane the divider sits on: a pane above the divider
/// uses `.bottom`, so dragging down grows it. The grab area extends past the hairline on
/// both sides without taking layout space; give the divider a `zIndex` above the pane
/// that follows it in the stack so that pane doesn't swallow the drag.
struct AppResizableDivider: View {
    @Binding var length: CGFloat
    let edge: Edge
    let clamp: (CGFloat) -> CGFloat
    let accessibilityLabel: String
    var adjustmentStep: CGFloat = 16
    var onResizeEnded: () -> Void = {}

    @State private var dragStartLength: CGFloat?
    @Environment(\.displayScale) private var displayScale

    private static let hitAreaThickness: CGFloat = 10

    /// One device pixel, so the line renders on 1x displays where a 0.5pt line falls between pixels.
    private var lineThickness: CGFloat {
        1 / max(displayScale, 1)
    }

    private var isHorizontalLine: Bool {
        edge == .top || edge == .bottom
    }

    /// Sign applied to the drag translation so moving away from the pane grows it.
    private var growthDirection: CGFloat {
        edge == .bottom || edge == .trailing ? 1 : -1
    }

    var body: some View {
        Rectangle()
            .fill(AppColors.paneDivider)
            .frame(width: isHorizontalLine ? nil : lineThickness, height: isHorizontalLine ? lineThickness : nil)
            .frame(
                maxWidth: isHorizontalLine ? .infinity : nil,
                maxHeight: isHorizontalLine ? nil : .infinity
            )
            .overlay { hitArea }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(Int(length)) points")
            .accessibilityAdjustableAction(adjust)
    }

    private var hitArea: some View {
        Color.clear
            .frame(
                width: isHorizontalLine ? nil : Self.hitAreaThickness,
                height: isHorizontalLine ? Self.hitAreaThickness : nil
            )
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture)
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    (isHorizontalLine ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                case .ended:
                    NSCursor.pop()
                }
            }
            #endif
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let startLength = dragStartLength ?? length
                dragStartLength = startLength
                let translation = isHorizontalLine ? value.translation.height : value.translation.width
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    length = clamp(startLength + translation * growthDirection)
                }
            }
            .onEnded { _ in
                dragStartLength = nil
                onResizeEnded()
            }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            length = clamp(length + adjustmentStep)
        case .decrement:
            length = clamp(length - adjustmentStep)
        @unknown default:
            return
        }
        onResizeEnded()
    }
}
