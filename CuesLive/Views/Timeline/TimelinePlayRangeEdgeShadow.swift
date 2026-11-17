import SwiftUI

/// Short shadow cast past the out point, fading away from the line, so the played stretch looks
/// raised above what follows. The ruler draws this view; the lane grid and the live ruler draw
/// the same gradient with `TimelineGridPainter.fillEdgeShadow`.
struct TimelinePlayRangeEdgeShadow: View {
    static let width: CGFloat = 6

    private static let gradient = Gradient(colors: [AppColors.Timeline.playRangeEdgeShadow, .clear])

    var body: some View {
        LinearGradient(gradient: Self.gradient, startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false)
    }
}
