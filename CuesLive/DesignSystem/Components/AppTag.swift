import SwiftUI

extension View {
    /// Styles compact content as a tag: `AppSpacing.tagInsets` padding on `background`, in a capsule.
    /// Use it for every small label pill (section names, device names, shortcut badges) so they stay
    /// consistent.
    func appTag(_ background: some ShapeStyle) -> some View {
        appTag(background, in: Capsule())
    }

    /// Styles compact content as a tag in `shape`, for a tag that must match the geometry it is attached
    /// to, such as a flag on a square-cornered clip.
    func appTag(_ background: some ShapeStyle, in shape: some Shape) -> some View {
        padding(AppSpacing.tagInsets)
            .background(background, in: shape)
    }
}
