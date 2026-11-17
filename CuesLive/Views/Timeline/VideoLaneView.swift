import SwiftUI

/// The song's movie as one clip of thumbnails at the top of the editor. Pointer zones match the
/// audio clips: the top half places the insertion or drags a time-range selection, the bottom half
/// moves where the movie starts (snapped to beats unless Command is held).
@MainActor
struct VideoLaneView: View {
    private enum DragSpace {
        static let name = "videoLaneTimeline"
    }

    /// A press on the clip, and whether it has turned into a drag.
    private struct ClipPointer {
        let selectsRange: Bool
        var isDragging = false
    }

    let video: VideoTrack
    let fileURL: URL?
    let durationSeconds: TimeInterval?
    let aspectRatio: CGFloat
    let timelineDuration: TimeInterval
    let timelineContentWidth: CGFloat
    let laneHeight: CGFloat
    /// Top of this lane in `TimelineLayout.trackLanesCoordinateSpace`, for range selection.
    let laneOriginY: CGFloat
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    /// Locate, range selection and blank clicks go to the editor like an audio lane's.
    let actions: ClipLaneActions
    let onMoveStart: (TimeInterval) -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.timelineScrollModel) private var scrollModel
    @State private var thumbnails = VideoThumbnailStore()
    @State private var dragStart: TimeInterval?
    @State private var clipPointer: ClipPointer?
    @State private var isMarqueeDragging = false

    /// Most thumbnails drawn at once. The painted range holds far fewer at any zoom.
    private static let maximumThumbnails = 240
    /// Clip length drawn when the movie's length is not known yet.
    private static let unknownDuration: TimeInterval = 10

    private var safeDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    private var movieDuration: TimeInterval {
        durationSeconds ?? Self.unknownDuration
    }

    private var startSeconds: TimeInterval {
        dragStart ?? video.startSeconds
    }

    private var pointsPerSecond: CGFloat {
        timelineContentWidth / CGFloat(safeDuration)
    }

    private var clipRect: CGRect {
        // Not `TimelineLayout.xPosition`, which clamps at zero: a movie may start before the song.
        let x = CGFloat(startSeconds) * pointsPerSecond
        let width = max(CGFloat(movieDuration) * pointsPerSecond, 2)
        return CGRect(x: x, y: 0, width: width, height: max(laneHeight - TimelineLayout.laneDividerHeight, 0))
    }

    private var thumbnailHeight: CGFloat {
        max(clipRect.height - TimelineLayout.clipHeaderHeight, 0)
    }

    /// Thumbnails across the painted part of the clip, one per thumbnail width from the clip's
    /// start, so they hold still while the lane scrolls. Only that part has slots, so a deep zoom
    /// decodes and draws what is on screen rather than spreading slots over the whole movie.
    private var thumbnailSlots: ThumbnailSlots {
        guard durationSeconds != nil, fileURL != nil, thumbnailHeight >= 8 else { return ThumbnailSlots() }
        let rect = clipRect
        let width = max(thumbnailHeight * aspectRatio, 8)
        let painted = scrollModel?.paintedRange ?? rect.minX...rect.maxX
        let lower = max(0, painted.lowerBound - rect.minX)
        let upper = min(rect.width, painted.upperBound - rect.minX)
        guard upper > lower else { return ThumbnailSlots() }
        let first = Int(floor(lower / width))
        let end = min(Int(ceil(upper / width)), first + Self.maximumThumbnails)
        let times = (first..<end).map { index in
            VideoThumbnailStore.gridSeconds(min(Double(CGFloat(index) * width / pointsPerSecond), movieDuration - 0.05))
        }
        let originX = CGFloat(first) * width
        return ThumbnailSlots(times: times, originX: originX, width: width, stripWidth: min(rect.width, CGFloat(end) * width) - originX)
    }

    var body: some View {
        let rect = clipRect
        ZStack(alignment: .topLeading) {
            blankSpace
            clipBody(in: rect)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX)
                #if os(macOS)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        cursor(atLaneY: location.y).apply()
                    case .ended:
                        ClipPointerCursor.reset()
                    }
                }
                #endif
                .gesture(clipPointerGesture)
        }
        .frame(width: timelineContentWidth, height: laneHeight, alignment: .topLeading)
        .coordinateSpace(name: DragSpace.name)
        .background(AppColors.Video.laneBody.opacity(0.12))
        .clipped()
        .task(id: thumbnailRequestKey) {
            requestThumbnails()
        }
    }

    private var thumbnailRequestKey: String {
        let times = thumbnailSlots.times
        return "\(fileURL?.path ?? "")|\(times.first ?? -1)|\(times.last ?? -1)|\(times.count)|\(laneHeight)|\(displayScale)"
    }

    private func requestThumbnails() {
        // Buckets of 16 px so resizing the lane does not decode again on every step.
        let pixels = Int(((thumbnailHeight * displayScale) / 16).rounded(.up) * 16)
        thumbnails.load(url: fileURL, times: thumbnailSlots.times, pixelHeight: min(max(pixels, 16), 512))
    }

    private func clipBody(in rect: CGRect) -> some View {
        VStack(spacing: 0) {
            Text(video.displayName)
                .font(AppTypography.Compact.label)
                .foregroundStyle(AppColors.Timeline.clipHeaderText)
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: TimelineLayout.clipHeaderHeight)
                .background(AppColors.Video.laneHeader)

            thumbnailStrip
        }
        .background(AppColors.Video.laneBody)
        .overlay {
            Rectangle()
                .stroke(AppColors.Video.laneHeader, lineWidth: TimelineLayout.clipBorderWidth)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnailStrip: some View {
        if fileURL == nil {
            Text("Video file missing")
                .font(AppTypography.Compact.label)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let slots = thumbnailSlots
            let images = thumbnails.images
            // As wide as the painted thumbnails, not the clip: a SwiftUI canvas wider than
            // 2^24 points draws nothing, and a deep zoom makes the clip far wider than that.
            Canvas { context, size in
                for (index, time) in slots.times.enumerated() {
                    let x = CGFloat(index) * slots.width
                    let frame = CGRect(x: x, y: 0, width: min(slots.width, size.width - x), height: size.height)
                    guard frame.width > 0 else { continue }
                    if let image = images[VideoThumbnailStore.key(forSeconds: time)] {
                        context.drawLayer { layer in
                            layer.clip(to: Path(frame))
                            layer.draw(
                                Image(decorative: image, scale: 1),
                                in: CGRect(x: x, y: 0, width: slots.width, height: size.height)
                            )
                        }
                    } else {
                        context.fill(Path(frame.insetBy(dx: 1, dy: 1)), with: .color(AppColors.Video.thumbnailPlaceholder))
                    }
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                        with: .color(AppColors.Video.thumbnailSeparator)
                    )
                }
            }
            .frame(width: max(slots.stripWidth, 0))
            .offset(x: slots.originX)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The top half selects like an audio clip; the bottom half moves. There are no trim handles.
    private func cursor(atLaneY y: CGFloat) -> ClipPointerCursor {
        y < laneHeight / 2 ? .select : .move
    }

    /// Clicking blank space places the insertion on this lane. On macOS, dragging there selects
    /// a time range. Touch drags are left to the scroll view.
    @ViewBuilder
    private var blankSpace: some View {
        let area = Color.clear
            .frame(width: timelineContentWidth, height: laneHeight)
            .contentShape(Rectangle())
        #if os(macOS)
        area
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    ClipPointerCursor.select.apply()
                case .ended:
                    ClipPointerCursor.reset()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(TimelineLayout.trackLanesCoordinateSpace))
                    .onChanged { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        guard isMarqueeDragging || distance >= 3 else { return }
                        isMarqueeDragging = true
                        ClipPointerCursor.select.apply()
                        actions.marquee(value.startLocation, value.location, .current)
                    }
                    .onEnded { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        if isMarqueeDragging || distance >= 3 {
                            isMarqueeDragging = false
                            ClipPointerCursor.reset()
                            actions.endMarquee()
                        } else {
                            actions.clickBlank(video.id, snappedTime(atContentX: value.location.x))
                        }
                    }
            )
        #else
        area.onTapGesture(coordinateSpace: .local) { location in
            actions.clickBlank(video.id, snappedTime(atContentX: location.x))
        }
        #endif
    }

    /// Top half: a click places the insertion and a drag selects a time range across lanes.
    /// Bottom half: a drag moves the movie's start.
    private var clipPointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(DragSpace.name))
            .onChanged { value in
                if clipPointer == nil {
                    let selectsRange = cursor(atLaneY: value.startLocation.y) == .select
                    clipPointer = ClipPointer(selectsRange: selectsRange)
                    if selectsRange {
                        actions.locate(video.id, snappedTime(atContentX: value.startLocation.x))
                    }
                }
                guard var pointer = clipPointer else { return }
                let distance = hypot(value.translation.width, value.translation.height)
                guard pointer.isDragging || distance >= 3 else { return }
                pointer.isDragging = true
                clipPointer = pointer
                if pointer.selectsRange {
                    ClipPointerCursor.select.apply()
                    actions.marquee(
                        CGPoint(x: value.startLocation.x, y: value.startLocation.y + laneOriginY),
                        CGPoint(x: value.location.x, y: value.location.y + laneOriginY),
                        PointerModifiers()
                    )
                    return
                }
                ClipPointerCursor.move.apply()
                let delta = TimeInterval(value.translation.width / pointsPerSecond)
                dragStart = snapped(video.startSeconds + delta)
            }
            .onEnded { value in
                guard let pointer = clipPointer else { return }
                clipPointer = nil
                guard pointer.isDragging else {
                    // A click is an insertion, so the range selection does not stay underneath it.
                    if pointer.selectsRange {
                        actions.clickBlank(video.id, snappedTime(atContentX: value.location.x))
                    }
                    return
                }
                ClipPointerCursor.reset()
                if pointer.selectsRange {
                    actions.endMarquee()
                    return
                }
                guard let dragStart else { return }
                self.dragStart = nil
                if abs(dragStart - video.startSeconds) > 0.0005 {
                    onMoveStart(dragStart)
                }
            }
    }

    private func snappedTime(atContentX x: CGFloat) -> TimeInterval {
        MeasureTiming.snapToNearestBeat(
            TimelineLayout.time(at: x, duration: safeDuration, contentWidth: timelineContentWidth),
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }

    /// Beat-snapped unless Command is held. The movie may start before the song, so negative times are kept.
    private func snapped(_ time: TimeInterval) -> TimeInterval {
        guard !PointerModifiers.current.command, time > 0 else { return time }
        return MeasureTiming.snapToNearestBeat(
            time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }
}

/// The thumbnails a video lane draws: movie times left to right, starting `originX` into the clip.
private struct ThumbnailSlots {
    var times: [TimeInterval] = []
    var originX: CGFloat = 0
    var width: CGFloat = 0
    /// From the first slot to the end of the last, or of the clip.
    var stripWidth: CGFloat = 0
}
