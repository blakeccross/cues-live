import SwiftUI

/// Short shadow cast past the out point, fading away from the line, so the played stretch looks
/// raised above what follows. The ruler draws this view; the lane shade draws the same gradient
/// in its canvas.
struct TimelinePlayRangeEdgeShadow: View {
    static let width: CGFloat = 6

    private static let gradient = Gradient(colors: [AppColors.Timeline.playRangeEdgeShadow, .clear])

    /// The gradient for a canvas, darkest at `rect`'s leading edge.
    static func shading(across rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(
            gradient,
            startPoint: CGPoint(x: rect.minX, y: rect.midY),
            endPoint: CGPoint(x: rect.maxX, y: rect.midY)
        )
    }

    var body: some View {
        LinearGradient(gradient: Self.gradient, startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false)
    }
}
