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
    @State private var thumbnails = VideoThumbnailStore()
    @State private var dragStart: TimeInterval?
    @State private var clipPointer: ClipPointer?
    @State private var isMarqueeDragging = false

    /// More thumbnails than this are spread out with gaps instead of decoding every slot.
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

    /// Movie times of the thumbnail slots, left to right, and the spacing between them.
    private var thumbnailSlots: (times: [TimeInterval], step: CGFloat) {
        guard durationSeconds != nil, fileURL != nil, thumbnailHeight >= 8 else { return ([], 0) }
        let width = max(thumbnailHeight * aspectRatio, 8)
        let count = min(Int((clipRect.width / width).rounded(.up)), Self.maximumThumbnails)
        guard count > 0 else { return ([], 0) }
        let step = max(width, clipRect.width / CGFloat(count))
        let times = (0..<count).map { index in
            VideoThumbnailStore.gridSeconds(min(Double(CGFloat(index) * step / pointsPerSecond), movieDuration - 0.05))
        }
        return (times, step)
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
        "\(fileURL?.path ?? "")|\(timelineContentWidth)|\(laneHeight)|\(movieDuration)|\(aspectRatio)|\(displayScale)"
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
            let width = thumbnailHeight * aspectRatio
            Canvas { context, size in
                for (index, time) in slots.times.enumerated() {
                    let x = CGFloat(index) * slots.step
                    let frame = CGRect(x: x, y: 0, width: min(width, size.width - x), height: size.height)
                    guard frame.width > 0 else { continue }
                    if let image = images[VideoThumbnailStore.key(forSeconds: time)] {
                        context.drawLayer { layer in
                            layer.clip(to: Path(frame))
                            layer.draw(
                                Image(decorative: image, scale: 1),
                                in: CGRect(x: x, y: 0, width: width, height: size.height)
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
