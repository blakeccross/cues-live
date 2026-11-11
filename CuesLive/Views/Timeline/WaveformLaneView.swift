import SwiftUI
#if os(macOS)
import AppKit
#endif

struct WaveformLaneView: View {
    private enum TimelineDragSpace {
        static let name = "waveformLaneTimeline"
    }

    @Bindable var track: AudioTrack

    let fileURL: URL
    let fileDuration: TimeInterval
    let timelineDuration: TimeInterval
    let timelineContentWidth: CGFloat
    /// This track's clips.
    let clips: [TrackClip]
    let sections: [SongSection]
    let selection: ClipSelection
    let clipDrag: ClipDrag?
    let actions: ClipLaneActions
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let laneHeight: CGFloat
    /// Top of this lane in the shared track-lane coordinate space.
    let laneOriginY: CGFloat
    let onCueSection: (SongSection) -> Void
    let loopSectionIDs: Set<UUID>
    let onToggleLoopSection: (SongSection) -> Void
    var shouldLoadWaveformPeaks = true

    @State private var overview = WaveformFileOverview(sampleRate: 0, channels: [])
    /// The file `overview` was built from.
    @State private var overviewURL: URL?
    @State private var isLoadingWaveformPeaks = false
    @State private var activeTrimEdge: (clipID: UUID, edge: ClipEditing.Edge)?
    @State private var clipPointer: ClipPointer?
    @State private var isMarqueeDragging = false

    private struct ClipPointer {
        let clipID: UUID
        let modifiers: PointerModifiers
        /// Press landed in the top half of the lane, so a drag selects a time range.
        let selectsRange: Bool
        /// Upper half, away from the trim handles. A click here places the insertion cursor.
        let movesPlayhead: Bool
        var isDragging = false
    }

    private var safeTimelineDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    /// Clips as drawn, with any in-progress drag on the selection applied.
    private var displayClips: [TrackClip] {
        var preview = clips
        guard let clipDrag else { return preview }
        let selectedHere = selection.clipIDs.intersection(clips.map(\.id))
        guard !selectedHere.isEmpty else { return preview }
        switch clipDrag {
        case .move(let delta, let copy):
            if copy {
                ClipEditing.copy(clipIDs: selectedHere, by: delta, in: &preview)
            } else {
                ClipEditing.move(clipIDs: selectedHere, by: delta, in: &preview)
            }
        case .trim(let edge, let delta):
            ClipEditing.trim(
                clipIDs: selectedHere,
                edge: edge,
                by: delta,
                sourceDuration: { _ in fileDuration },
                in: &preview
            )
        }
        return preview
    }

    var body: some View {
        waveformArea
            .onAppear {
                hydratePeaksFromCache()
            }
            .task(id: waveformLoadTaskID) {
                guard shouldLoadWaveformPeaks else { return }
                let url = fileURL
                if overviewURL == url, overview.channels.isEmpty == false { return }

                if let cached = WaveformCache.shared.cachedOverview(for: url) {
                    overview = cached
                    overviewURL = url
                    return
                }

                // The file changed (relink, consolidation, reused view): drop the old waveform.
                if overviewURL != url {
                    overview = WaveformFileOverview(sampleRate: 0, channels: [])
                }
                isLoadingWaveformPeaks = true
                defer { isLoadingWaveformPeaks = false }
                let loaded = await WaveformCache.shared.overview(for: url)
                guard !Task.isCancelled else { return }
                overview = loaded
                overviewURL = url
            }
    }

    private var waveformLoadTaskID: String {
        "\(fileURL.path)|\(shouldLoadWaveformPeaks)"
    }

    private var waveformArea: some View {
        ZStack(alignment: .topLeading) {
            blankSpace
            clipLayer
        }
        .frame(width: timelineContentWidth, height: laneHeight)
        .coordinateSpace(name: TimelineDragSpace.name)
    }

    /// Clicking blank space clears the selection. On macOS, dragging there selects a time range
    /// that stays after the pointer goes up. Touch drags are left to the scroll view.
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
                        actions.clickBlank(track.id, snappedTime(atContentX: value.location.x))
                    }
                }
        )
        #else
        area.onTapGesture(coordinateSpace: .local) { location in
            actions.clickBlank(track.id, snappedTime(atContentX: location.x))
        }
        #endif
    }

    private func timelineTime(atContentX x: CGFloat) -> TimeInterval {
        TimelineLayout.time(
            at: x,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
    }

    private func snappedTime(atContentX x: CGFloat) -> TimeInterval {
        MeasureTiming.snapToNearestBeat(
            timelineTime(atContentX: x),
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }

    private var clipLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(displayClips) { clip in
                clipView(for: clip)
            }
        }
        .frame(width: timelineContentWidth, height: laneHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func clipView(for clip: TrackClip) -> some View {
        let startX = TimelineLayout.xPosition(
            for: clip.timelineStartSeconds,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
        let endX = TimelineLayout.xPosition(
            for: clip.timelineEndSeconds,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
        let section = sections.section(atTimeline: clip.timelineStartSeconds + ClipEditing.tolerance)

        clipChrome(clip: clip, clipWidth: max(0, endX - startX), contentX: startX)
            .gesture(clipPointerGesture(for: clip, clipWidth: max(0, endX - startX), contentX: startX))
            .contextMenu {
                Button("Split") { actions.menu(.split, clip.id) }
                Button("Join") { actions.menu(.join, clip.id) }
                Button("Duplicate") { actions.menu(.duplicate, clip.id) }
                Button("Adjust Gain…") { actions.menu(.adjustGain, clip.id) }
                Button("Delete", role: .destructive) { actions.menu(.delete, clip.id) }
                if let section {
                    Divider()
                    Button("Cue \(section.name)") {
                        onCueSection(section)
                    }
                    Button(loopSectionIDs.contains(section.id) ? "Remove Loop" : "Loop \(section.name)") {
                        onToggleLoopSection(section)
                    }
                }
            }
            .offset(x: startX)
    }

    private func clipChrome(clip: TrackClip, clipWidth: CGFloat, contentX: CGFloat) -> some View {
        let paletteKey = track.group?.paletteKey
        let palette = TrackGroupPalette.colors(forPaletteKey: paletteKey)
        let selectedHeaderColor = TrackGroupPalette.selectedHeaderColor(forPaletteKey: paletteKey)
        let isSelected = selection.contains(clip.id)
        let clipHeight = max(
            0,
            laneHeight - TimelineLayout.clipLaneInset * 2 - TimelineLayout.laneDividerHeight
        )

        return VStack(spacing: 0) {
            clipHeader(
                clip: clip,
                headerColor: isSelected ? selectedHeaderColor : palette.header,
                isSelected: isSelected,
                clipWidth: clipWidth
            )
            .frame(width: clipWidth, height: TimelineLayout.clipHeaderHeight)

            ClipSampleWaveform(
                fileURL: fileURL,
                overview: overview,
                sourceStart: clip.sourceStartSeconds,
                sourceDuration: clip.duration,
                contentX: contentX,
                clipWidth: clipWidth,
                linearGain: clip.linearGain,
                showsBaseline: isLoadingWaveformPeaks || overview.channels.isEmpty
            )
            .frame(width: clipWidth, height: max(0, clipHeight - TimelineLayout.clipHeaderHeight))
            .allowsHitTesting(false)
        }
        .background(palette.body, in: RoundedRectangle(cornerRadius: TimelineLayout.clipCornerRadius, style: .continuous))
        .overlay {
            if isSelected {
                // Left, right, and bottom edges in the header's light color; the header itself
                // is the top edge, so the border and header read as one frame.
                RoundedRectangle(cornerRadius: TimelineLayout.clipCornerRadius, style: .continuous)
                    .strokeBorder(selectedHeaderColor, lineWidth: TimelineLayout.clipSelectionBorderWidth)
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: TimelineLayout.clipHeaderHeight)
                            Color.black
                        }
                    }
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: TimelineLayout.clipCornerRadius, style: .continuous)
                    .strokeBorder(palette.header.opacity(0.6), lineWidth: TimelineLayout.clipBorderWidth)
                    .mask {
                        // Keep the fill flush with the top edge so it lines up with the track name.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: TimelineLayout.clipBorderWidth)
                            Color.black
                        }
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: clipWidth, height: clipHeight, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            clipGainChrome(clip: clip, clipWidth: clipWidth, clipHeight: clipHeight)
        }
        .contentShape(Rectangle())
        .padding(.vertical, TimelineLayout.clipLaneInset)
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                ClipPointerCursor.zone(
                    at: location,
                    clipWidth: clipWidth,
                    laneHeight: laneHeight
                ).apply()
            case .ended:
                ClipPointerCursor.reset()
            }
        }
        #endif
    }

    private enum ClipHeaderEdge {
        case leading
        case trailing

        var icon: String {
            switch self {
            case .leading: return "["
            case .trailing: return "]"
            }
        }

        var editEdge: ClipEditing.Edge {
            switch self {
            case .leading: return .leading
            case .trailing: return .trailing
            }
        }
    }

    private func clipHeader(
        clip: TrackClip,
        headerColor: Color,
        isSelected: Bool,
        clipWidth: CGFloat
    ) -> some View {
        // Dark text on the light selected header, like Logic; muted white on the plain header.
        let foregroundColor = isSelected
            ? Color.black.opacity(0.72)
            : Color.white.opacity(0.65)

        return ZStack {
            headerColor

            Text(track.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                clipHeaderEdgeTrim(edge: .leading, clip: clip, foregroundColor: foregroundColor, clipWidth: clipWidth)
                Spacer(minLength: 0)
                clipHeaderEdgeTrim(edge: .trailing, clip: clip, foregroundColor: foregroundColor, clipWidth: clipWidth)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: TimelineLayout.clipCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: TimelineLayout.clipCornerRadius,
                style: .continuous
            )
        )
    }

    private func clipHeaderEdgeTrim(
        edge: ClipHeaderEdge,
        clip: TrackClip,
        foregroundColor: Color,
        clipWidth: CGFloat
    ) -> some View {
        ClipHeaderEdgeTrimControl(
            icon: edge.icon,
            isActive: activeTrimEdge?.clipID == clip.id && activeTrimEdge?.edge == edge.editEdge,
            foregroundColor: foregroundColor,
            isEnabled: clipWidth >= 12,
            gesture: clipTrimDragGesture(for: clip, edge: edge.editEdge)
        )
    }

    /// The top half of a clip drags a time-range selection. The bottom half moves the selection
    /// (Command copies it). Option-click splits at the pointer. A click in the top half, away
    /// from the trim handles, places the insertion cursor. Play starts from there.
    private func clipPointerGesture(for clip: TrackClip, clipWidth: CGFloat, contentX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(TimelineDragSpace.name))
            .onChanged { value in
                let local = CGPoint(x: value.startLocation.x - contentX, y: value.startLocation.y)
                let distance = hypot(value.translation.width, value.translation.height)
                if clipPointer?.clipID != clip.id {
                    let modifiers = PointerModifiers.current
                    let zone = ClipPointerCursor.zone(at: local, clipWidth: clipWidth, laneHeight: laneHeight)
                    clipPointer = ClipPointer(
                        clipID: clip.id,
                        modifiers: modifiers,
                        selectsRange: value.startLocation.y < laneHeight / 2,
                        movesPlayhead: zone == .select
                    )
                    actions.press(clip.id, track.id, modifiers)
                    if zone == .select {
                        actions.locate(track.id, snappedTime(atContentX: value.startLocation.x))
                    }
                }
                guard var pointer = clipPointer, !pointer.modifiers.option else { return }
                guard pointer.isDragging || distance >= 3 else { return }
                pointer.isDragging = true
                clipPointer = pointer
                if pointer.selectsRange {
                    ClipPointerCursor.select.apply()
                    let originY = laneOriginY
                    actions.marquee(
                        CGPoint(x: value.startLocation.x, y: value.startLocation.y + originY),
                        CGPoint(x: value.location.x, y: value.location.y + originY),
                        PointerModifiers()
                    )
                    return
                }
                guard let original = clips.first(where: { $0.id == clip.id }) else { return }
                ClipPointerCursor.move.apply()
                let rawDelta = timelineTime(atContentX: value.location.x) - timelineTime(atContentX: value.startLocation.x)
                actions.drag(.move(reference: original, rawDelta: rawDelta, copy: PointerModifiers.current.command))
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard let pointer = clipPointer else { return }
                clipPointer = nil
                // Option-click splits even if the pointer drifted. A real drag keeps the selection.
                if !pointer.modifiers.option && (pointer.isDragging || distance >= 3) {
                    ClipPointerCursor.reset()
                    if pointer.selectsRange {
                        actions.endMarquee()
                    } else {
                        actions.endDrag()
                    }
                } else {
                    let time = snappedTime(atContentX: value.location.x)
                    if pointer.movesPlayhead {
                        actions.locate(track.id, time)
                    }
                    actions.click(clip.id, pointer.modifiers, time)
                }
            }
    }

    @ViewBuilder
    private func clipGainChrome(clip: TrackClip, clipWidth: CGFloat, clipHeight: CGFloat) -> some View {
        let bodyHeight = clipHeight - TimelineLayout.clipHeaderHeight
        let showMark = ClipGain.showsLine(decibels: clip.gainDB)
        ZStack(alignment: .topLeading) {
            if showMark && bodyHeight > 12 {
                let y = TimelineLayout.clipHeaderHeight + CGFloat(
                    ClipGain.lineY(decibels: clip.gainDB, bodyHeight: Double(bodyHeight))
                )
                Canvas { context, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(.white.opacity(170.0 / 255.0)), lineWidth: 1)
                }
                .frame(width: clipWidth, height: clipHeight)
            }
            if showMark && clipWidth >= 48 && bodyHeight >= 30 {
                ClipGainIcon(decibels: clip.gainDB)
                    .padding(.leading, 4)
                    .padding(.top, max(clipHeight - 16, 0))
                    .frame(width: clipWidth, height: clipHeight, alignment: .topLeading)
            }
        }
        .frame(width: clipWidth, height: clipHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func clipTrimDragGesture(for clip: TrackClip, edge: ClipEditing.Edge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(TimelineDragSpace.name))
            .onChanged { value in
                guard let original = clips.first(where: { $0.id == clip.id }) else { return }
                if activeTrimEdge == nil {
                    activeTrimEdge = (clip.id, edge)
                    actions.press(clip.id, track.id, PointerModifiers())
                }
                ClipPointerCursor.trim.apply()
                actions.drag(.trim(reference: original, edge: edge, rawTime: timelineTime(atContentX: value.location.x)))
            }
            .onEnded { _ in
                activeTrimEdge = nil
                ClipPointerCursor.reset()
                actions.endDrag()
            }
    }

    private func hydratePeaksFromCache() {
        if let cached = WaveformCache.shared.cachedOverview(for: fileURL) {
            overview = cached
            overviewURL = fileURL
        }
    }
}

private struct ClipHeaderEdgeTrimControl<G: Gesture>: View {
    let icon: String
    let isActive: Bool
    let foregroundColor: Color
    let isEnabled: Bool
    let gesture: G

    @State private var isHovering = false

    var body: some View {
        Text(icon)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(foregroundColor.opacity(isActive ? 1 : 0.92))
            .frame(width: TimelineLayout.clipTrimHandleWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(gesture)
            #if os(macOS)
            .opacity(isEnabled && (isHovering || isActive) ? 1 : 0)
            .onContinuousHover { phase in
                guard isEnabled else { return }
                switch phase {
                case .active:
                    isHovering = true
                    ClipPointerCursor.trim.apply()
                case .ended:
                    isHovering = false
                }
            }
            #else
            .opacity(isEnabled && isActive ? 1 : 0)
            #endif
    }
}
