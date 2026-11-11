import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Extra viewports of waveform kept painted around the scroll position.
/// Scrolling inside that slice does not redraw the lanes.
enum TimelineHorizontalPaint {
    static let marginScreens: CGFloat = 2

    static func range(
        keeping painted: ClosedRange<CGFloat>,
        offset: CGFloat,
        viewportWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        guard viewportWidth > 0 else { return painted }
        let origin = max(0, offset)
        let visible = origin...(origin + viewportWidth)
        // Repaint while a margin of already-drawn waveform is still on screen.
        let lead = viewportWidth * 0.5
        let comfortLower = painted.lowerBound + lead
        let comfortUpper = painted.upperBound - lead
        if comfortLower <= visible.lowerBound, comfortUpper >= visible.upperBound {
            return painted
        }
        let margin = viewportWidth * marginScreens
        return max(0, origin - margin)...(origin + viewportWidth + margin)
    }
}

/// Scroll position for the rulers and the playhead.
/// The lane tree does not read `offset`, so a horizontal tick does not rebuild it.
@Observable
final class TimelineHorizontalScrollModel {
    var offset: CGFloat = 0
    private(set) var paintedRange: ClosedRange<CGFloat> = 0...8_192
    private var viewportWidth: CGFloat = 0

    func setViewportWidth(_ width: CGFloat) {
        let width = max(0, width)
        guard abs(viewportWidth - width) > 0.5 else { return }
        viewportWidth = width
        guard width > 0 else { return }
        let margin = width * TimelineHorizontalPaint.marginScreens
        let origin = max(0, offset)
        paintedRange = max(0, origin - margin)...(origin + width + margin)
    }

    func setOffset(_ newOffset: CGFloat) {
        if offset != newOffset {
            offset = newOffset
        }
        let updated = TimelineHorizontalPaint.range(
            keeping: paintedRange,
            offset: newOffset,
            viewportWidth: viewportWidth
        )
        if updated != paintedRange {
            paintedRange = updated
        }
    }
}

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

struct EditStemTimelineView<Ruler: View, TimeRuler: View, Lanes: View, HeaderCorner: View, TimeRulerCorner: View, Headers: View>: View {
    let timelineDuration: TimeInterval
    let timelineContentWidth: CGFloat
    let timelineDisplayWidth: CGFloat
    let sectionTimes: [TimeInterval]
    let laneHeights: [CGFloat]
    @Binding var timelineViewportWidth: CGFloat
    @FocusState.Binding var isTimelineFocused: Bool
    @ViewBuilder let ruler: () -> Ruler
    @ViewBuilder let timeRuler: () -> TimeRuler
    @ViewBuilder let lanes: () -> Lanes
    @ViewBuilder let headerRulerCorner: () -> HeaderCorner
    @ViewBuilder let timeRulerCorner: () -> TimeRulerCorner
    @ViewBuilder let headers: () -> Headers

    @State private var scrollModel = TimelineHorizontalScrollModel()

    private let timelineHorizontalScrollSpace = "editTimelineHorizontalScroll"

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

                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(spacing: 0) {
                                horizontalScrollOffsetProbe
                                lanes()
                                    .environment(\.timelineScrollModel, scrollModel)
                                    .frame(width: timelineDisplayWidth, height: laneAreaHeight, alignment: .topLeading)
                            }
                            .frame(width: timelineDisplayWidth, height: laneAreaHeight, alignment: .topLeading)
                            .background(TimelineScrollEdgeClamp())
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                        .contentMargins(0, for: .scrollContent)
                        .coordinateSpace(name: timelineHorizontalScrollSpace)
                        .applyTimelineHorizontalOffsetObserver { scrollModel.setOffset($0) }
                        .frame(width: timelineColumnWidth, height: laneAreaHeight)
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
                    TimelineSectionMarkerLines(
                        times: sectionTimes,
                        duration: timelineDuration,
                        contentWidth: timelineContentWidth,
                        horizontalScrollOffset: scrollModel.offset,
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

    /// Older systems report the horizontal offset with a preference.
    /// macOS 15 and iOS 18 read it from scroll geometry, and a live preference
    /// inside the lanes forces a layout pass on every tick.
    @ViewBuilder
    private var horizontalScrollOffsetProbe: some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            EmptyView()
        } else {
            TimelineHorizontalScrollOffsetReporter(
                coordinateSpaceName: timelineHorizontalScrollSpace
            )
        }
    }
}

extension View {
    @ViewBuilder
    func applyTimelineHorizontalOffsetObserver(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
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

private struct TimelineScrollModelKey: EnvironmentKey {
    static let defaultValue: TimelineHorizontalScrollModel? = nil
}

extension EnvironmentValues {
    /// Horizontal scroll model for the editor. Waveforms read `paintedRange` only.
    var timelineScrollModel: TimelineHorizontalScrollModel? {
        get { self[TimelineScrollModelKey.self] }
        set { self[TimelineScrollModelKey.self] = newValue }
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

struct TimelineHorizontalScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

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
