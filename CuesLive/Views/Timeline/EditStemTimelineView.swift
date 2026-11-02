import SwiftUI

struct TimelineHorizontalFollower<Content: View>: View {
    let contentWidth: CGFloat
    let scrollOffset: CGFloat
    let viewportWidth: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: contentWidth, alignment: .leading)
            .offset(x: -scrollOffset)
            .frame(width: viewportWidth, alignment: .leading)
            .clipped()
    }
}

struct EditStemTimelineView<Ruler: View, Lanes: View, HeaderCorner: View, Headers: View>: View {
    let timelineDuration: TimeInterval
    let timelineContentWidth: CGFloat
    let timelineDisplayWidth: CGFloat
    @Binding var timelineViewportWidth: CGFloat
    @FocusState.Binding var isTimelineFocused: Bool
    @ViewBuilder let ruler: () -> Ruler
    @ViewBuilder let lanes: () -> Lanes
    @ViewBuilder let headerRulerCorner: () -> HeaderCorner
    @ViewBuilder let headers: () -> Headers

    @State private var timelineHorizontalOffset: CGFloat = 0

    private let timelineHorizontalScrollSpace = "editTimelineHorizontalScroll"

    var body: some View {
        GeometryReader { geometry in
            let timelineColumnWidth = max(0, geometry.size.width - TimelineLayout.trackHeaderWidth)
            let tracksViewportHeight = max(0, geometry.size.height - TimelineLayout.rulerTotalHeight)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    TimelineHorizontalFollower(
                        contentWidth: timelineDisplayWidth,
                        scrollOffset: timelineHorizontalOffset,
                        viewportWidth: timelineColumnWidth
                    ) {
                        ruler()
                            .frame(width: timelineDisplayWidth, height: TimelineLayout.rulerTotalHeight)
                    }

                    headerRulerCorner()
                }

                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(spacing: 0) {
                                TimelineHorizontalScrollOffsetReporter(
                                    coordinateSpaceName: timelineHorizontalScrollSpace
                                )
                                lanes()
                                    .frame(width: timelineDisplayWidth, alignment: .leading)
                            }
                        }
                        .coordinateSpace(name: timelineHorizontalScrollSpace)
                        .applyTimelineHorizontalOffsetObserver { timelineHorizontalOffset = $0 }
                        .frame(width: timelineColumnWidth)

                        headers()
                            .frame(width: TimelineLayout.trackHeaderWidth)
                    }
                }
                .frame(height: tracksViewportHeight)
            }
            .overlay(alignment: .topLeading) {
                TimelinePlayheadTimeReader { playheadTime in
                    TimelinePlayheadOverlay(
                        playheadTime: playheadTime,
                        duration: timelineDuration,
                        contentWidth: timelineContentWidth,
                        height: TimelineLayout.rulerTotalHeight + tracksViewportHeight,
                        horizontalScrollOffset: timelineHorizontalOffset
                    )
                    .frame(width: timelineColumnWidth, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(0, proxy.size.width - TimelineLayout.trackHeaderWidth)
            } action: { width in
                timelineViewportWidth = width
            }
            .onTapGesture {
                isTimelineFocused = true
            }
        }
        .frame(maxHeight: .infinity)
    }
}

extension View {
    @ViewBuilder
    func applyTimelineHorizontalOffsetObserver(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, newValue in
                onChange(max(0, newValue))
            }
        } else {
            self.onPreferenceChange(TimelineHorizontalScrollOffsetKey.self) { newValue in
                onChange(max(0, newValue))
            }
        }
    }
}

struct TimelineHorizontalScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TimelineHorizontalScrollOffsetReporter: View {
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TimelineHorizontalScrollOffsetKey.self,
                value: -proxy.frame(in: .named(coordinateSpaceName)).minX
            )
        }
        .frame(width: 0, height: 0)
    }
}
