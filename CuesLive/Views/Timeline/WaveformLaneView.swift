import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TrackLaneHeaderView: View {
    @Bindable var track: AudioTrack
    @Bindable private var audioEngine = AudioEngineManager.shared
    let laneHeight: CGFloat
    let isSelected: Bool
    let groups: [TrackGroup]
    let onSelect: (PointerModifiers) -> Void
    let onMixChange: () -> Void
    let onGroupChange: () -> Void
    let onManageGroups: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var trackColors: (header: Color, body: Color) {
        TrackGroupPalette.colors(for: track.group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(trackColors.body)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TrackMixButton(
                        label: "M",
                        isActive: track.isMuted,
                        activeColor: .dawMuteActive
                    ) {
                        track.isMuted.toggle()
                        onMixChange()
                    }

                    TrackMixButton(
                        label: "S",
                        isActive: track.isSolo,
                        activeColor: .dawSoloActive
                    ) {
                        track.isSolo.toggle()
                        onMixChange()
                    }

                    TrackVolumeField(
                        volume: $track.volume,
                        onLiveChange: applyLiveMix,
                        onEditingEnded: onMixChange
                    )

                    TrackPanField(
                        pan: $track.pan,
                        onLiveChange: applyLiveMix,
                        onEditingEnded: onMixChange
                    )
                }

                groupPicker
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .frame(width: TimelineLayout.trackHeaderWidth, height: laneHeight, alignment: .topLeading)
        .background {
            if isSelected {
                Rectangle()
                    .fill(Color.dawTrackHeaderSelected)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") {
                onRename()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .onTapGesture { onSelect(.current) }
    }

    private func applyLiveMix() {
        audioEngine.applyLiveTrackMix(id: track.id, volume: Float(track.volume), pan: Float(track.pan))
    }

    private var groupPicker: some View {
        Menu {
            Button("No Group") {
                track.group = nil
                onGroupChange()
            }

            ForEach(groups) { group in
                Button(group.name) {
                    track.group = group
                    onGroupChange()
                }
            }

            Divider()

            Button("Manage Groups…") {
                onManageGroups()
            }
        } label: {
            HStack(spacing: 4) {
                Text(track.group?.name ?? "No Group")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.caption2)
            .foregroundStyle(trackColors.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.dawMixButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }
}

/// Modifier keys held at the moment of a pointer event. Always empty on iOS.
struct PointerModifiers: Equatable {
    var shift = false
    var command = false
    var option = false

    static var current: PointerModifiers {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        return PointerModifiers(
            shift: flags.contains(.shift),
            command: flags.contains(.command),
            option: flags.contains(.option)
        )
        #else
        return PointerModifiers()
        #endif
    }
}

/// The pointer's job on a clip, matching Soundcraft's smart tool.
enum ClipPointerCursor: Equatable {
    case select
    case move
    case trim

    /// Trim handles own the header ends. The top half of the lane selects a range; the bottom half moves.
    static func zone(
        at location: CGPoint,
        clipWidth: CGFloat,
        laneHeight: CGFloat,
        headerHeight: CGFloat = TimelineLayout.clipHeaderHeight,
        edgeWidth: CGFloat = TimelineLayout.clipTrimHandleWidth
    ) -> ClipPointerCursor {
        let onHeaderEdge = location.y >= 0
            && location.y <= headerHeight
            && clipWidth >= edgeWidth * 2
            && (location.x <= edgeWidth || location.x >= clipWidth - edgeWidth)
        if onHeaderEdge {
            return .trim
        }
        if location.y < laneHeight / 2 {
            return .select
        }
        return .move
    }

    func apply() {
        #if os(macOS)
        switch self {
        case .select: NSCursor.iBeam.set()
        case .move: NSCursor.openHand.set()
        case .trim: NSCursor.resizeLeftRight.set()
        }
        #endif
    }

    static func reset() {
        #if os(macOS)
        NSCursor.arrow.set()
        #endif
    }
}

/// An in-progress drag on the clip selection, already snapped and clamped.
enum ClipDrag: Equatable {
    case move(delta: TimeInterval, copy: Bool)
    case trim(edge: ClipEditing.Edge, delta: TimeInterval)
}

/// A raw drag reported by a lane. `reference` is the clip under the pointer; the editor snaps
/// its position and applies the same change to every selected clip.
enum ClipDragRequest {
    case move(reference: TrackClip, rawDelta: TimeInterval, copy: Bool)
    case trim(reference: TrackClip, edge: ClipEditing.Edge, rawTime: TimeInterval)
}

enum ClipMenuAction {
    case splitAtPlayhead
    case duplicate
    case join
    case delete
}

/// What a lane reports back to the editor, which owns the clip selection.
struct ClipLaneActions {
    /// Pointer-down on a clip.
    var press: (_ clipID: UUID, _ trackID: UUID, _ modifiers: PointerModifiers) -> Void
    /// Pointer-up on a clip without a drag. `time` is the snapped pointer position.
    var click: (_ clipID: UUID, _ modifiers: PointerModifiers, _ time: TimeInterval) -> Void
    var drag: (ClipDragRequest) -> Void
    var endDrag: () -> Void
    /// Time-range drag across lanes, in `TimelineLayout.trackLanesCoordinateSpace`.
    var marquee: (_ start: CGPoint, _ current: CGPoint, _ modifiers: PointerModifiers) -> Void
    /// The pointer went up after a range drag. The edit selection stays.
    var endMarquee: () -> Void
    /// Click on blank lane space at a snapped timeline time.
    var clickBlank: (_ trackID: UUID, _ time: TimeInterval) -> Void
    /// Selector press. Places the insertion cursor on this track at the snapped beat.
    var locate: (_ trackID: UUID, _ time: TimeInterval) -> Void
    var menu: (_ action: ClipMenuAction, _ clipID: UUID) -> Void
}

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
    /// Row in the lane stack, MIDI lanes included, so a drag can cross tracks.
    let rowIndex: Int
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
        /// Upper half, away from the trim handles. Soundcraft's selector places the playhead here.
        let movesPlayhead: Bool
        var isDragging = false
    }

    private var laneOriginY: CGFloat {
        CGFloat(rowIndex) * (laneHeight + TimelineLayout.laneSpacing)
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
                Button("Split at Playhead") { actions.menu(.splitAtPlayhead, clip.id) }
                Button("Join") { actions.menu(.join, clip.id) }
                Button("Duplicate") { actions.menu(.duplicate, clip.id) }
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
                if clipPointer?.clipID != clip.id {
                    let modifiers = PointerModifiers.current
                    let local = CGPoint(x: value.startLocation.x - contentX, y: value.startLocation.y)
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
                let distance = hypot(value.translation.width, value.translation.height)
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
                guard let pointer = clipPointer else { return }
                clipPointer = nil
                let distance = hypot(value.translation.width, value.translation.height)
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

/// One band per channel. Zoomed out, each pixel column is the real min and max in that window.
/// Zoomed to about a sample per pixel, the column is replaced by the samples themselves.
private struct ClipSampleWaveform: View {
    let fileURL: URL
    let overview: WaveformFileOverview
    let sourceStart: TimeInterval
    let sourceDuration: TimeInterval
    /// The clip's x origin in timeline-content coordinates.
    let contentX: CGFloat
    let clipWidth: CGFloat
    let showsBaseline: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.timelineScrollModel) private var scrollModel
    @State private var sampleStrips: [[Float]] = []
    @State private var sampleOrigin: Int = 0

    var body: some View {
        let visibleContentX = scrollModel?.paintedRange
        Canvas { context, size in
            draw(in: &context, size: size, visibleContentX: visibleContentX)
        }
        .task(id: sampleTaskID(visibleContentX: visibleContentX)) {
            await loadSamplesIfNeeded(visibleContentX: visibleContentX)
        }
    }

    private var scale: CGFloat { max(displayScale, 1) }

    private var sourceFrames: Double {
        max(0, sourceDuration) * overview.sampleRate
    }

    private func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        visibleContentX: ClosedRange<CGFloat>?
    ) {
        let channels = max(overview.channels.count, 1)
        let bandHeight = size.height / CGFloat(channels)
        for index in 0..<channels {
            let band = CGRect(x: 0, y: CGFloat(index) * bandHeight, width: size.width, height: bandHeight)
            let peaks = index < overview.channels.count ? overview.channels[index] : nil
            let samples = index < sampleStrips.count ? sampleStrips[index] : []
            drawChannel(
                peaks,
                samples: samples,
                in: band,
                context: &context,
                clipWidth: size.width,
                visibleContentX: visibleContentX
            )
        }
    }

    private func drawChannel(
        _ peaks: WaveformOverview?,
        samples: [Float],
        in band: CGRect,
        context: inout GraphicsContext,
        clipWidth: CGFloat,
        visibleContentX: ClosedRange<CGFloat>?
    ) {
        guard clipWidth > 0, band.height > 0, overview.sampleRate > 0, sourceFrames > 0 else {
            if showsBaseline { strokeBaseline(in: band, context: &context) }
            return
        }
        let window = visibleWindow(clipWidth: clipWidth, visibleContentX: visibleContentX)
        let framesPerPoint = sourceFrames / Double(clipWidth)
        let step = framesPerPoint / Double(scale)
        let overlap = max(0, framesPerPoint - step)
        let origin = sourceStart * overview.sampleRate
        let pixelStart = Int(floor(window.lower * scale))
        let pixelEnd = Int(ceil(window.upper * scale))
        let count = max(0, pixelEnd - pixelStart)
        // Soundcraft centers each column on its pixel and lets the window reach one point into its neighbours.
        let windowStart = origin + Double(pixelStart) / Double(scale) * framesPerPoint - overlap * 0.5
        let half = band.height * WaveformColumnGeometry.amplitudeFraction
        let centerY = band.midY
        let color = Color.white.opacity(0.55)

        if samples.count > 1, step <= 1 {
            var path = Path()
            var started = false
            for index in samples.indices {
                let frame = Double(sampleOrigin + index)
                let x = CGFloat((frame - origin) / sourceFrames) * clipWidth
                guard x >= window.lower - 1, x <= window.upper + 1 else { continue }
                let y = centerY - CGFloat(clamp(samples[index])) * half
                let point = CGPoint(x: x, y: y)
                if started {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
            }
            context.stroke(path, with: .color(color), lineWidth: max(1 / scale, 0.5))
            return
        }

        if samples.count > 1, let drawn = WaveformOverview.sampleColumns(
            samples: samples,
            origin: sampleOrigin,
            fileEnd: overview.channels.first?.sampleCount ?? samples.count,
            windowStart: windowStart,
            step: step,
            overlap: overlap,
            count: count
        ) {
            fillColumns(drawn, pixelStart: pixelStart, columnWidth: 1 / scale, centerY: centerY, half: half, color: color, context: &context)
            return
        }

        guard let peaks else {
            if showsBaseline { strokeBaseline(in: band, context: &context) }
            return
        }
        guard count > 0 else { return }
        let columns = peaks.columns(start: windowStart, step: step, overlap: overlap, count: count)
        fillColumns(columns, pixelStart: pixelStart, columnWidth: 1 / scale, centerY: centerY, half: half, color: color, context: &context)
    }

    private func fillColumns(
        _ columns: [(Float, Float)?],
        pixelStart: Int,
        columnWidth: CGFloat,
        centerY: CGFloat,
        half: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        var run: [WaveformColumnSpan] = []
        var runStart = 0

        func flush() {
            guard !run.isEmpty else { return }
            let path = Path(WaveformColumnGeometry.envelopePath(
                columns: run,
                originX: CGFloat(pixelStart + runStart) * columnWidth,
                columnWidth: columnWidth,
                centerY: centerY,
                half: half
            ))
            context.fill(path, with: .color(color))
            run.removeAll(keepingCapacity: true)
        }

        for (index, column) in columns.enumerated() {
            if let column {
                if run.isEmpty { runStart = index }
                run.append(WaveformColumnGeometry.thicken(
                    min: column.0,
                    max: column.1,
                    half: half,
                    scale: scale
                ))
            } else {
                flush()
            }
        }
        flush()
    }

    private func visibleWindow(
        clipWidth: CGFloat,
        visibleContentX: ClosedRange<CGFloat>?
    ) -> (lower: CGFloat, upper: CGFloat) {
        guard let visible = visibleContentX else { return (0, clipWidth) }
        let lower = max(0, visible.lowerBound - contentX)
        let upper = min(clipWidth, visible.upperBound - contentX)
        guard upper > lower else { return (0, 0) }
        return (lower, upper)
    }

    /// The frames of the file to load samples for, or `nil` while zoomed out far enough to use peaks.
    private func sampleRange(visibleContentX: ClosedRange<CGFloat>?) -> (first: Int, last: Int)? {
        guard overview.sampleRate > 0, sourceFrames > 1, clipWidth > 1 else { return nil }
        let window = visibleWindow(clipWidth: clipWidth, visibleContentX: visibleContentX)
        guard window.upper > window.lower else { return nil }
        let origin = sourceStart * overview.sampleRate
        let framesPerPoint = sourceFrames / Double(clipWidth)
        let pad = Int(ceil(framesPerPoint)) + 2
        let first = max(0, Int(floor(origin + Double(window.lower) * framesPerPoint)) - pad)
        let last = Int(ceil(origin + Double(window.upper) * framesPerPoint)) + pad
        guard last > first, last - first <= 200_000 else { return nil }
        return (first, last)
    }

    private func sampleTaskID(visibleContentX: ClosedRange<CGFloat>?) -> String {
        guard let range = sampleRange(visibleContentX: visibleContentX) else { return "peaks" }
        return "samples|\(fileURL.path)|\(range.first)|\(range.last)"
    }

    private func loadSamplesIfNeeded(visibleContentX: ClosedRange<CGFloat>?) async {
        guard let range = sampleRange(visibleContentX: visibleContentX) else {
            sampleStrips = []
            return
        }
        let start = max(0, range.first - 1)
        let count = min(range.last - start + 2, 200_000)
        let channelCount = overview.channels.count
        let url = fileURL
        let strips = await Task.detached(priority: .utility) {
            (0..<channelCount).map { channel in
                WaveformOverviewBuilder.samples(from: url, channel: channel, startFrame: start, count: count)
            }
        }.value
        // The read can't be cancelled; drop it if a newer window or file has taken over.
        guard !Task.isCancelled else { return }
        sampleOrigin = start
        sampleStrips = strips
    }

    private func strokeBaseline(in band: CGRect, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: band.minX, y: band.midY))
        path.addLine(to: CGPoint(x: band.maxX, y: band.midY))
        context.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
    }

    private func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(-1, value))
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
