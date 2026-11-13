import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TimelineHorizontalFollower<Content: View>: View {
    var model: TimelineHorizontalScrollModel
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    private let content: Content

    init(
        model: TimelineHorizontalScrollModel,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.contentWidth = contentWidth
        self.viewportWidth = viewportWidth
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: contentWidth, alignment: .leading)
            .offset(x: -model.offset)
            .frame(width: viewportWidth, alignment: .leading)
            .clipped()
            .animation(nil, value: model.offset)
    }
}

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
    let sectionTimes: [TimeInterval]
    let laneHeights: [CGFloat]
    /// False hides the playing playhead, for a song the engine is not playing.
    var showsPlayhead = true
    @Binding var timelineViewportWidth: CGFloat
    @FocusState.Binding var isTimelineFocused: Bool
    /// Command- or Option-scroll over the lanes, with the factor to multiply the zoom by.
    let onWheelZoom: (CGFloat) -> Void
    @ViewBuilder let ruler: () -> Ruler
    @ViewBuilder let timeRuler: () -> TimeRuler
    /// Clip bodies and waveforms, drawn viewport-wide behind the lanes.
    let laneCanvas: TimelineLaneCanvas
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
                HStack(alignment: .top, spacing: 0) {
                    headerRulerCorner()

                    TimelineHorizontalFollower(
                        model: scrollModel,
                        contentWidth: timelineDisplayWidth,
                        viewportWidth: timelineColumnWidth
                    ) {
                        ruler()
                            .frame(width: timelineDisplayWidth, height: TimelineLayout.topRulerHeight)
                    }
                }

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
                .overlay(alignment: .topLeading) {
                    TimelineSectionMarkerFollower(
                        model: scrollModel,
                        times: sectionTimes,
                        duration: timelineDuration,
                        contentWidth: timelineContentWidth,
                        viewportWidth: timelineColumnWidth
                    )
                    .frame(height: tracksViewportHeight)
                    .padding(.leading, TimelineLayout.trackHeaderWidth)
                    .allowsHitTesting(false)
                }

                HStack(alignment: .top, spacing: 0) {
                    timeRulerCorner()

                    TimelineHorizontalFollower(
                        model: scrollModel,
                        contentWidth: timelineDisplayWidth,
                        viewportWidth: timelineColumnWidth
                    ) {
                        timeRuler()
                            .frame(width: timelineDisplayWidth, height: TimelineLayout.rulerHeight)
                    }
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.dawTimelineDivider)
                        .frame(height: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsPlayhead {
                    TimelineFollowingPlayhead(
                        model: scrollModel,
                        duration: timelineDuration,
                        contentWidth: timelineContentWidth,
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

    /// One dark rule per track, spanning the name column and the visible waveform.
    private var trackLaneDividers: some View {
        VStack(spacing: 0) {
            ForEach(Array(laneFrames.rows.enumerated()), id: \.offset) { _, row in
                Color.clear
                    .frame(height: max(row.height - TimelineLayout.laneDividerHeight, 0))
                Rectangle()
                    .fill(Color.dawTrackLaneDivider)
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
            canvas: laneCanvas,
            onScroll: { scrollModel.setOffset($0) },
            onWheelZoom: onWheelZoom,
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

/// Section-marker lines over the lane viewport. This view, not the container, reads the
/// scroll offset, so a tick redraws these lines without rebuilding the lanes and headers.
private struct TimelineSectionMarkerFollower: View {
    var model: TimelineHorizontalScrollModel
    let times: [TimeInterval]
    let duration: TimeInterval
    let contentWidth: CGFloat
    let viewportWidth: CGFloat

    var body: some View {
        TimelineSectionMarkerLines(
            times: times,
            duration: duration,
            contentWidth: contentWidth,
            horizontalScrollOffset: model.offset,
            viewportWidth: viewportWidth
        )
    }
}

/// Red playhead pinned to the viewport, drawn only while audio is playing.
private struct TimelineFollowingPlayhead: View {
    @Bindable private var audioEngine = AudioEngineManager.shared
    var model: TimelineHorizontalScrollModel
    let duration: TimeInterval
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    let height: CGFloat

    var body: some View {
        if audioEngine.isPlaying {
            let offset = model.offset
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

/// Stops the enclosing scroll view from moving past its content.
private struct TimelineScrollEdgeClamp: View {
    var body: some View {
        TimelineScrollEdgeClampRepresentable()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }
}

#if os(macOS)
private struct TimelineScrollEdgeClampRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> TimelineScrollEdgeClampView {
        TimelineScrollEdgeClampView()
    }

    func updateNSView(_ view: TimelineScrollEdgeClampView, context: Context) {
        view.clampEnclosingScrollView()
    }
}

private final class TimelineScrollEdgeClampView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        clampEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clampEnclosingScrollView()
    }

    override func layout() {
        super.layout()
        clampEnclosingScrollView()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func clampEnclosingScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
    }
}
#else
private struct TimelineScrollEdgeClampRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> TimelineScrollEdgeClampView {
        TimelineScrollEdgeClampView()
    }

    func updateUIView(_ view: TimelineScrollEdgeClampView, context: Context) {
        view.clampEnclosingScrollView()
    }
}

private final class TimelineScrollEdgeClampView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        clampEnclosingScrollView()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clampEnclosingScrollView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clampEnclosingScrollView()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    func clampEnclosingScrollView() {
        var ancestor: UIView? = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                scrollView.bounces = false
                scrollView.alwaysBounceHorizontal = false
                scrollView.alwaysBounceVertical = false
                return
            }
            ancestor = view.superview
        }
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
