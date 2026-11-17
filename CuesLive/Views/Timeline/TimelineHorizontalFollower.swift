import SwiftUI

/// Ruler content that scrolls with the lanes.
///
/// The follower inside reads the scroll offset, so a scroll tick moves the content without
/// rebuilding it. A live zoom leaves it at the editor's zoom, under the AppKit ruler that
/// follows the zoom on screen.
struct TimelineHorizontalFollower<Content: View>: View {
    var model: TimelineHorizontalScrollModel
    /// Content width before display padding.
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    /// Builds the content for a content width and a display width.
    @ViewBuilder let content: (CGFloat, CGFloat) -> Content

    var body: some View {
        let displayWidth = max(contentWidth, viewportWidth)
        TimelineOffsetFollower(model: model, width: displayWidth, viewportWidth: viewportWidth) {
            content(contentWidth, displayWidth)
        }
    }
}

/// Moves prebuilt content with the scroll offset and clips it to the viewport.
private struct TimelineOffsetFollower<Content: View>: View {
    var model: TimelineHorizontalScrollModel
    let width: CGFloat
    let viewportWidth: CGFloat
    private let content: Content

    init(
        model: TimelineHorizontalScrollModel,
        width: CGFloat,
        viewportWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.width = width
        self.viewportWidth = viewportWidth
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.timelineScrollModel, model)
            .frame(width: width, alignment: .leading)
            .offset(x: -model.offset)
            .frame(width: viewportWidth, alignment: .leading)
            .clipped()
            .animation(nil, value: model.offset)
    }
}
