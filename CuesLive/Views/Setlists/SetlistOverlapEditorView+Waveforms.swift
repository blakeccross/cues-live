import SwiftUI

/// The two-lane waveform editor. Both songs sit on one `OverlapEditorTimeline`. The lanes are drawn
/// at viewport size from the scroll offset, like the setlist strip, so a long song never becomes one
/// huge canvas; a transparent scroll view above them carries scrolling and the incoming lane's drag.
extension SetlistOverlapEditorView {
    var waveformEditor: some View {
        Group {
            if isLoadingWaveforms {
                ProgressView("Loading waveforms…")
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
            } else {
                waveformEditorContent
            }
        }
        .frame(height: waveformEditorHeight)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .clipped()
    }

    private var waveformEditorHeight: CGFloat {
        Self.laneHeight * 2 + Self.laneSpacing
    }

    /// Editor time at the viewport's left edge, unclamped so the lanes follow the scroll bounce.
    private var scrolledTime: TimeInterval {
        guard pointsPerSecond > 0 else { return 0 }
        return focusRange.lowerBound + TimeInterval(scrollOffset / pointsPerSecond)
    }

    /// Scroll-content x of an editor time. The content spans only `focusRange`.
    private func contentX(for time: TimeInterval) -> CGFloat {
        CGFloat(time - focusRange.lowerBound) * pointsPerSecond
    }

    private var waveformEditorContent: some View {
        ZStack(alignment: .topLeading) {
            visibleLanes
            previewPlayhead
            if viewportWidth > 0 {
                interactionLayer
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            viewportWidth = width
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overlap waveforms")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                zoomOut()
            case .decrement:
                zoomIn()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Drawing

    private var visibleLanes: some View {
        VStack(spacing: Self.laneSpacing) {
            lane(title: context.outgoingSong.name, snapshot: outgoingSnapshot, entry: 0)
            lane(title: context.incomingSong.name, snapshot: incomingSnapshot, entry: timeline.incomingEntry)
        }
        .allowsHitTesting(false)
    }

    /// One song's lane across the viewport. `entry` is the editor time where the song starts.
    @ViewBuilder
    private func lane(title: String, snapshot: LiveSongWaveformSnapshot?, entry: TimeInterval) -> some View {
        if let snapshot {
            OverlapWaveformLaneView(
                title: title,
                snapshot: snapshot,
                startTime: snapshot.window.start + scrolledTime - entry,
                pointsPerSecond: pointsPerSecond,
                width: viewportWidth,
                height: Self.laneHeight,
                playheadTime: snapshot.window.start + playheadPosition - entry
            )
        } else {
            AppColors.LiveWaveform.background
                .frame(height: Self.laneHeight)
                .overlay {
                    Text("No waveform")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
        }
    }

    @ViewBuilder
    private var previewPlayhead: some View {
        if isTimeVisible(playheadPosition) {
            TimelinePlayheadOverlay(
                playheadTime: playheadPosition - scrolledTime,
                duration: max(windowDuration, 0.001),
                contentWidth: viewportWidth,
                height: waveformEditorHeight
            )
            .allowsHitTesting(false)
        }
    }

    // MARK: - Scrolling and dragging

    private var interactionLayer: some View {
        let contentWidth = max(viewportWidth, contentX(for: focusRange.upperBound))

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: contentWidth, height: waveformEditorHeight)

                    incomingDragTarget

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(ScrollTarget.transitionCenter)
                        .padding(.leading, contentX(for: timeline.transitionCenter))

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(ScrollTarget.seekPosition)
                        .padding(.leading, contentX(for: seekTime))

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(ScrollTarget.leadingTime)
                        .padding(.leading, max(0, contentX(for: pendingLeadingTime ?? focusRange.lowerBound)))
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    -proxy.frame(in: .named(ScrollTarget.coordinateSpace)).minX
                } action: { offset in
                    scrollOffset = offset
                }
            }
            .coordinateSpace(name: ScrollTarget.coordinateSpace)
            .scrollBounceBehavior(.basedOnSize)
            .simultaneousGesture(pinchZoomGesture)
            .onAppear {
                // Wait for the content's first layout, or the scroll lands short of the target.
                Task { centerTransition(proxy: proxy) }
            }
            // Opening, resizing and zooming center the transition. Dragging the incoming lane
            // leaves the scroll where the user put it.
            .onChange(of: transitionCenterRequest) {
                centerTransition(proxy: proxy)
            }
            // Keeps the same stretch on screen after the focus range moves under it.
            .onChange(of: pendingLeadingTime) {
                guard pendingLeadingTime != nil else { return }
                proxy.scrollTo(ScrollTarget.leadingTime, anchor: .leading)
                pendingLeadingTime = nil
            }
            .onChange(of: viewportWidth) {
                centerTransition(proxy: proxy)
            }
            .onChange(of: windowZoom) {
                centerTransition(proxy: proxy)
            }
            // Scrubbing somewhere off screen brings the playhead back into view.
            .onChange(of: seekTime) {
                guard isScrubbing, !isTimeVisible(seekTime) else { return }
                proxy.scrollTo(ScrollTarget.seekPosition, anchor: .center)
            }
        }
    }

    /// Covers the incoming lane, so dragging it moves where the song enters. Cut to the focus range,
    /// so a long song doesn't widen the scroll content.
    private var incomingDragTarget: some View {
        let visibleEnd = min(timeline.incomingEntry + timeline.incomingLength, focusRange.upperBound)
        return Color.clear
            .frame(width: max(0, CGFloat(visibleEnd - timeline.incomingEntry) * pointsPerSecond), height: Self.laneHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(incomingDragGesture)
            .accessibilityLabel(context.incomingSong.name)
            .accessibilityHint("Drag to set where this song comes in.")
            .padding(.leading, contentX(for: timeline.incomingEntry))
            .padding(.top, Self.laneHeight + Self.laneSpacing)
    }

    private func isTimeVisible(_ time: TimeInterval) -> Bool {
        time >= scrolledTime && time <= scrolledTime + windowDuration
    }

    private func centerTransition(proxy: ScrollViewProxy) {
        proxy.scrollTo(ScrollTarget.transitionCenter, anchor: .center)
    }

    private var incomingDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = startOffsetSeconds
                }
                guard let dragStartOffset, pointsPerSecond > 0 else { return }
                let startEntry = timeline.outgoingLength - dragStartOffset
                let deltaTime = TimeInterval(value.translation.width / pointsPerSecond)
                // The focus range holds still during the drag, so the entry stays inside it.
                let entry = max(focusRange.lowerBound, startEntry + deltaTime)
                startOffsetSeconds = timeline.startOffset(incomingEntry: entry)
            }
            .onEnded { _ in
                dragStartOffset = nil
                let leadingTime = scrolledTime
                updateFocusRange()
                pendingLeadingTime = leadingTime
                invalidatePreviewConfiguration()
            }
    }

    // MARK: - Zoom

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if pinchStartZoom == nil {
                    pinchStartZoom = windowZoom
                }
                guard let pinchStartZoom else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    windowZoom = clampedWindowZoom(pinchStartZoom / scale)
                }
            }
            .onEnded { _ in
                pinchStartZoom = nil
            }
    }

    var canZoomIn: Bool {
        windowZoom > Self.minimumWindowZoom
    }

    var canZoomOut: Bool {
        windowZoom < maximumWindowZoom
    }

    /// Shortens the visible window so the overlap fills more of the editor.
    func zoomIn() {
        setWindowZoom(windowZoom / Self.zoomButtonFactor)
    }

    /// Lengthens the visible window to show more of both songs.
    func zoomOut() {
        setWindowZoom(windowZoom * Self.zoomButtonFactor)
    }

    private func setWindowZoom(_ proposed: CGFloat) {
        let clamped = clampedWindowZoom(proposed)
        guard clamped != windowZoom else { return }
        windowZoom = clamped
    }
}

private enum ScrollTarget: Hashable {
    case transitionCenter
    case seekPosition
    case leadingTime

    static let coordinateSpace = "overlap-editor-scroll"
}
