import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditStemTimelineView<
    Ruler: View,
    TimeRuler: View,
    Lanes: View,
    HeaderCorner: View,
    TimeRulerCorner: View,
    Headers: View
>: View {
    let timelineDuration: TimeInterval
    let timelineContentWidth: CGFloat
    let timelineDisplayWidth: CGFloat
    let timelineZoom: CGFloat
    let timelineZoomRange: ClosedRange<CGFloat>
    let laneHeights: [CGFloat]
    /// False hides the playing playhead, for a song the engine is not playing.
    var showsPlayhead = true
    @Binding var timelineViewportWidth: CGFloat
    @FocusState.Binding var isTimelineFocused: Bool
    /// Sets the editor's zoom when a pinch or Command-scroll over the lanes pauses, on macOS.
    let onCommitZoom: (CGFloat) -> Void
    /// Built for a content width and a display width, so a live zoom can lay the rulers out
    /// again without rebuilding the editor.
    @ViewBuilder let ruler: (CGFloat, CGFloat) -> Ruler
    @ViewBuilder let timeRuler: (CGFloat, CGFloat) -> TimeRuler
    /// Clip bodies and waveforms, drawn viewport-wide behind the lanes.
    let laneCanvas: TimelineLaneCanvas
    /// What the rulers show, for the AppKit ruler drawn during a live zoom on macOS.
    let liveRuler: TimelineLiveRuler
    /// Clip chrome and gestures, laid out across the whole timeline and scrolled.
    @ViewBuilder let lanes: () -> Lanes
    @ViewBuilder let headerRulerCorner: () -> HeaderCorner
    @ViewBuilder let timeRulerCorner: () -> TimeRulerCorner
    @ViewBuilder let headers: () -> Headers

    @State private var scrollModel = TimelineHorizontalScrollModel()

    #if os(iOS)
    private let timelineHorizontalScrollSpace = "editTimelineHorizontalScroll"
    #endif

    private var laneFrames: TrackLaneFrames {
        TrackLaneFrames(heights: laneHeights)
    }

    private var laneAreaHeight: CGFloat {
        laneFrames.totalHeight
    }

    var body: some View {
        GeometryReader { geometry in
            let timelineColumnWidth = max(0, geometry.size.width - TimelineLayout.trackHeaderWidth)
            let tracksViewportHeight = max(0, geometry.size.height - TimelineLayout.rulerTotalHeight)

            VStack(spacing: 0) {
                rulerRows(width: timelineColumnWidth)

                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        headers()
                            .frame(width: TimelineLayout.trackHeaderWidth, height: laneAreaHeight, alignment: .top)

                        laneScrollColumn(width: timelineColumnWidth)
                    }
                    .frame(height: laneAreaHeight, alignment: .top)
                    .background(TimelineScrollEdgeClamp())
                    .overlay(alignment: .topLeading) {
                        // Drawn on the row that holds both columns. A line inside either
                        // column is clipped before it can cross into the track names.
                        trackLaneDividers
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .contentMargins(0, for: .scrollContent)
                .frame(height: tracksViewportHeight)
            }
            .overlay(alignment: .topLeading) {
                if showsPlayhead {
                    TimelineFollowingPlayhead(
                        model: scrollModel,
                        duration: timelineDuration,
                        contentWidth: timelineContentWidth,
                        zoom: timelineZoom,
                        viewportWidth: timelineColumnWidth,
                        height: TimelineLayout.rulerTotalHeight + tracksViewportHeight
                    )
                    .padding(.leading, TimelineLayout.trackHeaderWidth)
                    .allowsHitTesting(false)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(0, proxy.size.width - TimelineLayout.trackHeaderWidth)
            } action: { width in
                timelineViewportWidth = width
                scrollModel.setViewportWidth(width)
            }
            .onTapGesture {
                isTimelineFocused = true
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The time ruler, then the meter, tempo and marker rulers, each scrolling with the lanes. On
    /// macOS the live ruler covers them during a live zoom, so they are not laid out every step.
    private func rulerRows(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                timeRulerCorner()

                TimelineHorizontalFollower(
                    model: scrollModel,
                    contentWidth: timelineContentWidth,
                    viewportWidth: width
                ) { contentWidth, displayWidth in
                    timeRuler(contentWidth, displayWidth)
                        .frame(width: displayWidth, height: TimelineLayout.rulerHeight)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColors.Timeline.divider)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }

            HStack(alignment: .top, spacing: 0) {
                headerRulerCorner()

                TimelineHorizontalFollower(
                    model: scrollModel,
                    contentWidth: timelineContentWidth,
                    viewportWidth: width
                ) { contentWidth, displayWidth in
                    ruler(contentWidth, displayWidth)
                        .frame(width: displayWidth, height: TimelineLayout.topRulerHeight)
                }
            }
        }
        #if os(macOS)
        .overlay(alignment: .topLeading) {
            TimelineLiveRulerLayer(ruler: liveRuler, scrollModel: scrollModel)
                .frame(width: width, height: TimelineLayout.rulerTotalHeight)
                .padding(.leading, TimelineLayout.trackHeaderWidth)
                .allowsHitTesting(false)
        }
        #endif
    }

    /// One dark rule per track, spanning the name column and the visible waveform.
    private var trackLaneDividers: some View {
        VStack(spacing: 0) {
            ForEach(Array(laneFrames.rows.enumerated()), id: \.offset) { _, row in
                Color.clear
                    .frame(height: max(row.height - TimelineLayout.laneDividerHeight, 0))
                Rectangle()
                    .fill(AppColors.Timeline.laneDivider)
                    .frame(maxWidth: .infinity)
                    .frame(height: TimelineLayout.laneDividerHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var laneContent: some View {
        lanes()
            .environment(\.timelineScrollModel, scrollModel)
            .frame(width: timelineDisplayWidth, height: laneAreaHeight, alignment: .topLeading)
    }

    /// The horizontally scrolling lane chrome over the lane canvas. On macOS an AppKit scroll
    /// view owns the axis and the canvas, so a trackpad tick moves a layer and redraws the
    /// canvas in the same event instead of re-laying out SwiftUI content.
    @ViewBuilder
    private func laneScrollColumn(width: CGFloat) -> some View {
        #if os(macOS)
        TimelineHorizontalScrollHost(
            contentWidth: timelineDisplayWidth,
            contentHeight: laneAreaHeight,
            zoom: timelineZoom,
            zoomRange: timelineZoomRange,
            canvas: laneCanvas,
            onScroll: { scrollModel.setOffset($0) },
            onLiveZoom: { scrollModel.setLiveZoom($0, laidOutAt: timelineZoom) },
            onCommitZoom: onCommitZoom,
            onPointerDown: { isTimelineFocused = true }
        ) {
            laneContent
        }
        .frame(width: width, height: laneAreaHeight)
        #else
        ZStack(alignment: .topLeading) {
            TimelineLaneCanvasLayer(canvas: laneCanvas, scrollModel: scrollModel)
                .frame(width: width, height: laneAreaHeight)
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    horizontalScrollOffsetProbe
                    laneContent
                }
                .frame(width: timelineDisplayWidth, height: laneAreaHeight, alignment: .topLeading)
                .background(TimelineScrollEdgeClamp())
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .contentMargins(0, for: .scrollContent)
            .coordinateSpace(name: timelineHorizontalScrollSpace)
            .applyTimelineHorizontalOffsetObserver { scrollModel.setOffset($0) }
            TimelineGridOverlayLayer(canvas: laneCanvas, scrollModel: scrollModel)
                .frame(width: width, height: laneAreaHeight)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: laneAreaHeight, alignment: .topLeading)
        #endif
    }

    #if os(iOS)
    /// Older systems report the horizontal offset with a preference.
    /// iOS 18 reads it from scroll geometry, and a live preference
    /// inside the lanes forces a layout pass on every tick.
    @ViewBuilder
    private var horizontalScrollOffsetProbe: some View {
        if #available(iOS 18.0, *) {
            EmptyView()
        } else {
            TimelineHorizontalScrollOffsetReporter(
                coordinateSpaceName: timelineHorizontalScrollSpace
            )
        }
    }
    #endif
}

#if os(iOS)
extension View {
    @ViewBuilder
    func applyTimelineHorizontalOffsetObserver(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, newValue in
                onChange(newValue)
            }
        } else {
            self.onPreferenceChange(TimelineHorizontalScrollOffsetKey.self) { newValue in
                onChange(newValue)
            }
        }
    }
}
#endif

/// Red playhead pinned to the viewport, drawn only while audio is playing.
private struct TimelineFollowingPlayhead: View {
    @Bindable private var audioEngine = AudioEngineManager.shared
    var model: TimelineHorizontalScrollModel
    let duration: TimeInterval
    let contentWidth: CGFloat
    /// The zoom `contentWidth` was laid out at.
    let zoom: CGFloat
    let viewportWidth: CGFloat
    let height: CGFloat

    var body: some View {
        if audioEngine.isPlaying {
            let offset = model.offset
            let contentWidth = model.liveWidth(contentWidth, laidOutAt: zoom)
            TimelinePlayheadTimeReader { playheadTime in
                TimelinePlayheadOverlay(
                    playheadTime: playheadTime,
                    duration: duration,
                    contentWidth: contentWidth,
                    height: height,
                    style: .line,
                    horizontalScrollOffset: offset,
                    canvasWidth: viewportWidth
                )
            }
            .animation(nil, value: offset)
        }
    }
}

#if os(iOS)
struct TimelineHorizontalScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif

#if os(iOS)
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
#endif
