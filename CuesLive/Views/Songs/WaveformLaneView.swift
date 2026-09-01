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
    let onSelect: () -> Void
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
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(trackColors.body)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            groupPicker

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

                LogicStyleVolumeSlider(
                    value: $track.volume,
                    meterLevel: audioEngine.trackMeterLevel(for: track.id),
                    onEditingEnded: onMixChange
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: TimelineLayout.trackHeaderWidth, height: laneHeight, alignment: .topLeading)
        .background {
            if isSelected {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.dawTrackHeaderSelected)

                    Rectangle()
                        .fill(trackColors.header)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
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
        .onTapGesture(perform: onSelect)
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

struct WaveformLaneView: View {
    private enum TimelineDragSpace {
        static let name = "waveformLaneTimeline"
    }

    @Bindable var track: AudioTrack

    let fileURL: URL
    let fileDuration: TimeInterval
    let timelineDuration: TimeInterval
    let timelineContentWidth: CGFloat
    let arrangementSections: [ArrangementDisplaySection]
    @Binding var arrangementSlots: [ArrangementSlot]
    @Binding var clipTrims: [ArrangementClipTrim]
    @Binding var clipGaps: [ArrangementClipGap]
    @Binding var clipRegions: [ClipRegion]
    @Binding var clipSelection: TimelineClipSelection?
    let markers: [ArrangementMarker]
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let laneHeight: CGFloat
    let onTrimChange: () -> Void
    let onCueSection: (ArrangementDisplaySection) -> Void
    let loopSlotIDs: Set<UUID>
    let onToggleLoopSection: (ArrangementDisplaySection) -> Void
    let onClipTrimCommitted: () -> Void
    let onSeek: (TimeInterval) -> Void
    var shouldLoadWaveformPeaks = true

    @Bindable private var audioEngine = AudioEngineManager.shared
    @State private var sourcePeaks: [Float] = []
    @State private var cachedDisplayPeaks: [Float] = []
    @State private var isLoadingWaveformPeaks = false
    @State private var activeHandle: TrimHandle?
    @State private var activeClipTrim: ActiveClipTrim?
    @State private var clipTrimDragStart: ClipTrimDragStart?
    @State private var previewClipTrims: PreviewClipTrims?
    @State private var activeClipRegionTrim: (regionID: UUID, edge: ClipRegionStore.RegionTrimEdge)?
    @State private var clipRegionTrimBaseline: ClipRegion?
    @State private var previewClipRegion: ClipRegion?
    @State private var activeClipDragSelection: ClipDragSelection?

    private struct ClipDragSelection: Equatable {
        let clipID: UUID
        let startX: CGFloat
        var currentX: CGFloat
    }

    private struct ActiveClipTrim: Equatable {
        let slotID: UUID
        let edge: ArrangementClipTrimEdge
    }

    private struct ClipTrimDragStart: Equatable {
        let leadingTrim: TimeInterval
        let trailingTrim: TimeInterval
    }

    private struct PreviewClipTrims: Equatable {
        let slotID: UUID
        let leading: TimeInterval
        let trailing: TimeInterval
    }

    private enum ArrangementClipTrimEdge {
        case leading
        case trailing
    }

    private enum TrimHandle {
        case start
        case end
    }

    private var clipBodyHeight: CGFloat {
        max(0, laneHeight - TimelineLayout.clipHeaderHeight)
    }

    private var effectiveEnd: TimeInterval {
        track.trimEndSeconds ?? fileDuration
    }

    private var safeTimelineDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    private var usesArrangementLayout: Bool {
        !arrangementSections.isEmpty
    }

    private var showsFullSourceWaveform: Bool {
        !usesArrangementLayout
    }

    private var displayPeaksCacheKey: String {
        let sectionKey = arrangementSections
            .map { "\($0.id.uuidString)|\($0.timelineStartSeconds)|\($0.timelineEndSeconds)" }
            .joined(separator: ",")
        let gapKey = clipGaps
            .filter { $0.trackID == track.id }
            .map { "\($0.sourceStartSeconds)|\($0.sourceEndSeconds)" }
            .joined(separator: ",")
        let regionKey = clipRegions
            .filter { $0.trackID == track.id }
            .map { "\($0.id.uuidString)|\($0.timelineStartSeconds)|\($0.timelineEndSeconds)" }
            .joined(separator: ",")
        let previewTrimKey = previewClipTrims.map {
            "\($0.slotID.uuidString)|\($0.leading)|\($0.trailing)"
        } ?? ""
        let trackTrimKey = "\(track.trimStartSeconds)|\(track.trimEndSeconds ?? -1)"
        return "\(timelineContentWidth)|\(timelineDuration)|\(fileDuration)|\(sourcePeaks.count)|\(sectionKey)|\(gapKey)|\(regionKey)|\(usesArrangementLayout)|\(previewTrimKey)|\(trackTrimKey)"
    }

    private func refreshCachedDisplayPeaks() {
        if showsFullSourceWaveform {
            cachedDisplayPeaks = WaveformPeakResampler.displayPeaks(
                from: sourcePeaks,
                contentWidth: timelineContentWidth
            )
        } else {
            cachedDisplayPeaks = WaveformPeakResampler.arrangedDisplayPeaks(
                from: sourcePeaks,
                fileDuration: fileDuration,
                sections: arrangementSections,
                timelineDuration: safeTimelineDuration,
                contentWidth: timelineContentWidth
            )
        }
    }

    var body: some View {
        waveformArea
            .onAppear {
                hydratePeaksFromCache()
                refreshCachedDisplayPeaks()
            }
            .task(id: waveformLoadTaskID) {
                guard shouldLoadWaveformPeaks else { return }

                if let cached = WaveformCache.shared.cachedPeaks(for: fileURL) {
                    sourcePeaks = cached
                    refreshCachedDisplayPeaks()
                    return
                }

                isLoadingWaveformPeaks = true
                defer { isLoadingWaveformPeaks = false }

                sourcePeaks = await WaveformCache.shared.peaks(for: fileURL)
                refreshCachedDisplayPeaks()
            }
            .onChange(of: displayPeaksCacheKey) { _, _ in
                refreshCachedDisplayPeaks()
            }
    }

    private var waveformLoadTaskID: String {
        "\(fileURL.path)|\(shouldLoadWaveformPeaks)"
    }

    private func clipDisplayPeaks(timelineStart: TimeInterval, timelineEnd: TimeInterval) -> [Float] {
        WaveformPeakResampler.peaksSlice(
            from: cachedDisplayPeaks,
            timelineStart: timelineStart,
            timelineEnd: timelineEnd,
            timelineDuration: safeTimelineDuration
        )
    }

    private var waveformArea: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: timelineContentWidth, height: laneHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    clipSelection = nil
                }

            clipLayer
        }
        .frame(width: timelineContentWidth, height: laneHeight)
        .coordinateSpace(name: TimelineDragSpace.name)
    }

    private func timelineTime(atContentX x: CGFloat) -> TimeInterval {
        TimelineLayout.time(
            at: x,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
    }

    private var clipLayer: some View {
        ZStack(alignment: .leading) {
            if usesArrangementLayout {
                ForEach(arrangementSections) { section in
                    arrangementClip(for: section)
                }
            } else {
                ForEach(sourceTrackClipSegments, id: \.id) { segment in
                    sourceTrackClipSegment(segment)
                }
            }
        }
        .frame(width: timelineContentWidth, height: laneHeight, alignment: .leading)
    }

    private struct SourceClipSegment: Identifiable {
        let id: UUID
        let slotID: UUID
        let timelineStart: TimeInterval
        let timelineEnd: TimeInterval
        let sourceStart: TimeInterval
        let sourceEnd: TimeInterval
    }

    private var sourceTrackClipSegments: [SourceClipSegment] {
        let sections = SongArrangementStore.sourceTrackDisplaySections(
            trackID: track.id,
            trimStart: track.trimStartSeconds,
            trimEnd: effectiveEnd,
            clipGaps: clipGaps,
            clipRegions: clipRegions
        )
        if sections.isEmpty {
            return [
                SourceClipSegment(
                    id: track.id,
                    slotID: track.id,
                    timelineStart: track.trimStartSeconds,
                    timelineEnd: effectiveEnd,
                    sourceStart: track.trimStartSeconds,
                    sourceEnd: effectiveEnd
                ),
            ]
        }
        return sections.map { section in
            SourceClipSegment(
                id: section.id,
                slotID: section.slotID,
                timelineStart: section.timelineStartSeconds,
                timelineEnd: section.timelineEndSeconds,
                sourceStart: section.sourceStartSeconds,
                sourceEnd: section.sourceEndSeconds
            )
        }
    }

    private func sourceTrackClipSegment(_ segment: SourceClipSegment) -> some View {
        let bounds = resolvedClipBounds(clipID: segment.id, fallbackStart: segment.timelineStart, fallbackEnd: segment.timelineEnd)
        let startX = TimelineLayout.xPosition(
            for: bounds.start,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
        let endX = TimelineLayout.xPosition(
            for: bounds.end,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
        let clipWidth = max(0, endX - startX)

        return clipChrome(
            clipID: segment.id,
            slotID: segment.slotID,
            title: track.displayName,
            paletteKey: track.group?.paletteKey,
            clipWidth: clipWidth,
            timelineStart: bounds.start,
            timelineEnd: bounds.end,
            regionTrimBoundsStart: track.trimStartSeconds,
            regionTrimBoundsEnd: effectiveEnd,
            arrangementSection: nil,
            sourceTrimLeading: resolvedClipRegion(clipID: segment.id) == nil
                && segment.id == sourceTrackClipSegments.first?.id,
            sourceTrimTrailing: resolvedClipRegion(clipID: segment.id) == nil
                && segment.id == sourceTrackClipSegments.last?.id
        )
        .offset(x: startX)
    }

    @ViewBuilder
    private func arrangementClip(for section: ArrangementDisplaySection) -> some View {
        let bounds = clipTimelineBounds(for: section)
        let startX = TimelineLayout.xPosition(
            for: bounds.start,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
        let endX = TimelineLayout.xPosition(
            for: bounds.end,
            duration: safeTimelineDuration,
            contentWidth: timelineContentWidth
        )
        let clipWidth = max(0, endX - startX)

        clipChrome(
                clipID: section.id,
                slotID: section.slotID,
                title: track.displayName,
                paletteKey: track.group?.paletteKey,
                clipWidth: clipWidth,
                timelineStart: bounds.start,
                timelineEnd: bounds.end,
                regionTrimBoundsStart: section.columnStartSeconds,
                regionTrimBoundsEnd: section.columnEndSeconds,
                arrangementSection: resolvedClipRegion(clipID: section.id) == nil ? section : nil,
                sourceTrimLeading: false,
                sourceTrimTrailing: false
            )
            .contextMenu {
                Button("Cue Section") {
                    onCueSection(section)
                }
                if loopSlotIDs.contains(section.id) {
                    Button("Remove Loop") {
                        onToggleLoopSection(section)
                    }
                } else {
                    Button("Loop Section") {
                        onToggleLoopSection(section)
                    }
                }
            }
            .offset(x: startX)
    }

    private func clipChrome(
        clipID: UUID,
        slotID: UUID,
        title: String,
        paletteKey: String?,
        clipWidth: CGFloat,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval,
        regionTrimBoundsStart: TimeInterval,
        regionTrimBoundsEnd: TimeInterval,
        arrangementSection: ArrangementDisplaySection?,
        sourceTrimLeading: Bool,
        sourceTrimTrailing: Bool
    ) -> some View {
        let palette = TrackGroupPalette.colors(forPaletteKey: paletteKey)
        let selection = matchingClipSelection(for: clipID)
        let isSelected = selection != nil
        let isWholeSelected = selection?.isWholeClip == true
        let committedRange = committedSelectionRange(
            clipID: clipID,
            timelineStart: timelineStart,
            timelineEnd: timelineEnd
        )
        let dragRange = activeClipDragSelection.flatMap { drag in
            drag.clipID == clipID ? dragSelectionRange(
                drag: drag,
                clipWidth: clipWidth,
                timelineStart: timelineStart,
                timelineEnd: timelineEnd
            ) : nil
        }
        let clipHeight = laneHeight - TimelineLayout.clipLaneInset * 2

        return VStack(spacing: 0) {
            clipHeader(
                title: title,
                headerColor: palette.header,
                isSelected: isSelected,
                clipID: clipID,
                slotID: slotID,
                clipWidth: clipWidth,
                arrangementSection: arrangementSection,
                regionTrimBoundsStart: regionTrimBoundsStart,
                regionTrimBoundsEnd: regionTrimBoundsEnd,
                sourceTrimLeading: sourceTrimLeading,
                sourceTrimTrailing: sourceTrimTrailing
            )
            .frame(width: clipWidth, height: TimelineLayout.clipHeaderHeight)

            ZStack(alignment: .leading) {
                WaveformBarsCanvas(
                    bars: clipDisplayPeaks(timelineStart: timelineStart, timelineEnd: timelineEnd),
                    showsEmptyBaseline: showsFullSourceWaveform || isLoadingWaveformPeaks,
                    fillColor: Color.white.opacity(0.55)
                )
                .equatable()
                .allowsHitTesting(false)

                if isLoadingWaveformPeaks, sourcePeaks.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                if let dragRange {
                    selectionOverlay(
                        range: dragRange,
                        clipWidth: clipWidth,
                        timelineStart: timelineStart,
                        timelineEnd: timelineEnd
                    )
                } else if let committedRange, !isWholeSelected {
                    selectionOverlay(
                        range: committedRange,
                        clipWidth: clipWidth,
                        timelineStart: timelineStart,
                        timelineEnd: timelineEnd
                    )
                }
            }
            .frame(width: clipWidth, height: max(0, clipHeight - TimelineLayout.clipHeaderHeight))
            .contentShape(Rectangle())
            .gesture(
                clipBodySelectionGesture(
                    clipID: clipID,
                    slotID: slotID,
                    clipWidth: clipWidth,
                    timelineStart: timelineStart,
                    timelineEnd: timelineEnd
                )
            )
        }
        .background(palette.body, in: RoundedRectangle(cornerRadius: TimelineLayout.clipCornerRadius, style: .continuous))
        .overlay {
            let borderWidth = isWholeSelected
                ? TimelineLayout.clipSelectionBorderWidth
                : TimelineLayout.clipBorderWidth
            let borderColor = isWholeSelected
                ? AppColors.accent
                : palette.header.opacity(0.6)

            RoundedRectangle(cornerRadius: TimelineLayout.clipCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
                .padding(-borderWidth)
                .allowsHitTesting(false)
        }
        .frame(width: clipWidth, height: clipHeight, alignment: .topLeading)
        .padding(.vertical, TimelineLayout.clipLaneInset)
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
    }

    private func clipHeader(
        title: String,
        headerColor: Color,
        isSelected: Bool,
        clipID: UUID,
        slotID: UUID,
        clipWidth: CGFloat,
        arrangementSection: ArrangementDisplaySection?,
        regionTrimBoundsStart: TimeInterval,
        regionTrimBoundsEnd: TimeInterval,
        sourceTrimLeading: Bool,
        sourceTrimTrailing: Bool
    ) -> some View {
        let foregroundColor = isSelected
            ? Color.white.opacity(0.92)
            : Color.white.opacity(0.65)

        return ZStack {
            if isSelected {
                headerColor
            }

            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                clipHeaderEdgeTrim(
                    edge: .leading,
                    clipID: clipID,
                    arrangementSection: arrangementSection,
                    regionTrimBoundsStart: regionTrimBoundsStart,
                    regionTrimBoundsEnd: regionTrimBoundsEnd,
                    sourceTrimEnabled: sourceTrimLeading,
                    foregroundColor: foregroundColor,
                    clipWidth: clipWidth
                )
                Spacer(minLength: 0)
                clipHeaderEdgeTrim(
                    edge: .trailing,
                    clipID: clipID,
                    arrangementSection: arrangementSection,
                    regionTrimBoundsStart: regionTrimBoundsStart,
                    regionTrimBoundsEnd: regionTrimBoundsEnd,
                    sourceTrimEnabled: sourceTrimTrailing,
                    foregroundColor: foregroundColor,
                    clipWidth: clipWidth
                )
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
        .contentShape(Rectangle())
        .onTapGesture {
            selectWholeClip(clipID: clipID, slotID: slotID)
        }
    }

    @ViewBuilder
    private func clipHeaderEdgeTrim(
        edge: ClipHeaderEdge,
        clipID: UUID,
        arrangementSection: ArrangementDisplaySection?,
        regionTrimBoundsStart: TimeInterval,
        regionTrimBoundsEnd: TimeInterval,
        sourceTrimEnabled: Bool,
        foregroundColor: Color,
        clipWidth: CGFloat
    ) -> some View {
        if let region = resolvedClipRegion(clipID: clipID) {
            let trimEdge: ClipRegionStore.RegionTrimEdge = edge == .leading ? .leading : .trailing
            ClipHeaderEdgeTrimControl(
                icon: edge.icon,
                isActive: isClipRegionTrimActive(regionID: region.id, edge: trimEdge),
                foregroundColor: foregroundColor,
                isEnabled: clipWidth >= 12,
                gesture: clipRegionTrimDragGesture(
                    for: region,
                    edge: trimEdge,
                    boundsStart: regionTrimBoundsStart,
                    boundsEnd: regionTrimBoundsEnd
                )
            )
        } else if let arrangementSection {
            let trimEdge: ArrangementClipTrimEdge = edge == .leading ? .leading : .trailing
            ClipHeaderEdgeTrimControl(
                icon: edge.icon,
                isActive: isClipTrimActive(sectionID: arrangementSection.id, edge: trimEdge),
                foregroundColor: foregroundColor,
                isEnabled: clipWidth >= 12,
                gesture: clipTrimDragGesture(for: arrangementSection, edge: trimEdge)
            )
        } else if sourceTrimEnabled {
            let handle: TrimHandle = edge == .leading ? .start : .end
            ClipHeaderEdgeTrimControl(
                icon: edge.icon,
                isActive: activeHandle == handle,
                foregroundColor: foregroundColor,
                isEnabled: clipWidth >= 12,
                gesture: sourceTrackTrimDragGesture(handle: handle)
            )
        }
    }

    private func matchingClipSelection(for clipID: UUID) -> TimelineClipSelection? {
        guard let clipSelection,
              clipSelection.clipID == clipID,
              clipSelection.trackID == track.id else {
            return nil
        }
        return clipSelection
    }

    private func selectionOverlay(
        range: ClosedRange<TimeInterval>,
        clipWidth: CGFloat,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval
    ) -> some View {
        let duration = max(timelineEnd - timelineStart, 0.001)
        let startX = clipWidth * CGFloat((range.lowerBound - timelineStart) / duration)
        let endX = clipWidth * CGFloat((range.upperBound - timelineStart) / duration)
        let width = max(0, endX - startX)

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: width, height: clipBodyHeight)
                .offset(x: startX)

            Rectangle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: width, height: clipBodyHeight)
                .offset(x: startX)
        }
        .allowsHitTesting(false)
    }

    private func clipBodySelectionGesture(
        clipID: UUID,
        slotID: UUID,
        clipWidth: CGFloat,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startX = min(max(0, value.startLocation.x), clipWidth)
                let currentX = min(max(0, value.location.x), clipWidth)
                guard abs(currentX - startX) >= 4 else {
                    activeClipDragSelection = nil
                    return
                }
                if activeClipDragSelection?.clipID != clipID {
                    activeClipDragSelection = ClipDragSelection(
                        clipID: clipID,
                        startX: startX,
                        currentX: currentX
                    )
                } else if var drag = activeClipDragSelection {
                    drag.currentX = currentX
                    activeClipDragSelection = drag
                }
            }
            .onEnded { value in
                defer { activeClipDragSelection = nil }

                guard clipWidth > 0 else { return }
                let startX = min(max(0, value.startLocation.x), clipWidth)
                let endX = min(max(0, value.location.x), clipWidth)
                let minX = min(startX, endX)
                let maxX = max(startX, endX)

                if maxX - minX >= 4,
                   let range = dragSelectionRange(
                       drag: ClipDragSelection(clipID: clipID, startX: minX, currentX: maxX),
                       clipWidth: clipWidth,
                       timelineStart: timelineStart,
                       timelineEnd: timelineEnd
                   ) {
                    clipSelection = .range(
                        clipID: clipID,
                        slotID: slotID,
                        trackID: track.id,
                        start: range.lowerBound,
                        end: range.upperBound
                    )
                } else {
                    let time = snappedTimelineTime(
                        atX: startX,
                        clipWidth: clipWidth,
                        timelineStart: timelineStart,
                        timelineEnd: timelineEnd
                    )
                    if !audioEngine.isPlaying {
                        onSeek(time)
                    }
                    selectWholeClip(clipID: clipID, slotID: slotID, editTime: time)
                }
            }
    }

    private func snappedTimelineTime(
        atX x: CGFloat,
        clipWidth: CGFloat,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval
    ) -> TimeInterval {
        guard clipWidth > 0 else { return timelineStart }
        let duration = max(timelineEnd - timelineStart, 0.001)
        let clampedX = min(max(0, x), clipWidth)
        let raw = timelineStart + duration * TimeInterval(clampedX / clipWidth)
        let snapped = MeasureTiming.snapToNearestBeat(
            raw,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        return min(max(snapped, timelineStart), timelineEnd)
    }

    private func dragSelectionRange(
        drag: ClipDragSelection,
        clipWidth: CGFloat,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard clipWidth > 0 else { return nil }
        let duration = max(timelineEnd - timelineStart, 0.001)
        let minX = min(drag.startX, drag.currentX)
        let maxX = max(drag.startX, drag.currentX)
        let rawStart = timelineStart + duration * TimeInterval(minX / clipWidth)
        let rawEnd = timelineStart + duration * TimeInterval(maxX / clipWidth)
        let snapped = MeasureTiming.snapTimelineRangeToGrid(
            start: rawStart,
            end: rawEnd,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let start = max(timelineStart, snapped.start)
        let end = min(timelineEnd, snapped.end)
        guard end - start >= 0.05 else { return nil }
        return start...end
    }

    private func committedSelectionRange(
        clipID: UUID,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard let selection = matchingClipSelection(for: clipID),
              case .range(_, _, _, let start, let end) = selection else {
            return nil
        }
        let overlapStart = max(start, timelineStart)
        let overlapEnd = min(end, timelineEnd)
        guard overlapEnd - overlapStart >= 0.05 else { return nil }
        return overlapStart...overlapEnd
    }

    private func selectWholeClip(clipID: UUID, slotID: UUID, editTime: TimeInterval? = nil) {
        clipSelection = .whole(clipID: clipID, slotID: slotID, trackID: track.id, editTime: editTime)
    }

    private func sourceTrackTrimDragGesture(handle: TrimHandle) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(TimelineDragSpace.name))
            .onChanged { value in
                activeHandle = handle
                applyTrimTime(handle: handle, time: timelineTime(atContentX: value.location.x))
            }
            .onEnded { _ in
                activeHandle = nil
                onTrimChange()
            }
    }

    private func clipTrimDragGesture(
        for section: ArrangementDisplaySection,
        edge: ArrangementClipTrimEdge
    ) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(TimelineDragSpace.name))
            .onChanged { value in
                if activeClipTrim?.slotID != section.id || activeClipTrim?.edge != edge {
                    activeClipTrim = ActiveClipTrim(slotID: section.id, edge: edge)
                    let current = SongArrangementStore.trims(
                        slotID: section.id,
                        trackID: track.id,
                        in: clipTrims
                    )
                    clipTrimDragStart = ClipTrimDragStart(
                        leadingTrim: current.leading,
                        trailingTrim: current.trailing
                    )
                }

                guard let clipTrimDragStart,
                      let slot = arrangementSlots.first(where: { $0.id == section.slotID }),
                      let marker = markers.first(where: { $0.id == slot.markerID }) else { return }

                let timelineTime = timelineTime(atContentX: value.location.x)

                var leading = clipTrimDragStart.leadingTrim
                var trailing = clipTrimDragStart.trailingTrim

                switch edge {
                case .leading:
                    leading = timelineTime - section.columnStartSeconds
                case .trailing:
                    trailing = section.columnEndSeconds - timelineTime
                }

                let clamped: (leading: TimeInterval, trailing: TimeInterval) = {
                    var draftTrims = clipTrims
                    SongArrangementStore.setTrims(
                        slotID: section.id,
                        trackID: track.id,
                        leading: leading,
                        trailing: trailing,
                        in: &draftTrims
                    )
                    return SongArrangementStore.clampedTrims(
                        slotID: section.id,
                        trackID: track.id,
                        marker: marker,
                        markers: markers,
                        clipTrims: draftTrims,
                        sourceDuration: fileDuration
                    )
                }()
                previewClipTrims = PreviewClipTrims(
                    slotID: section.id,
                    leading: clamped.leading,
                    trailing: clamped.trailing
                )
            }
            .onEnded { _ in
                defer {
                    activeClipTrim = nil
                    clipTrimDragStart = nil
                    previewClipTrims = nil
                }

                guard let previewClipTrims, previewClipTrims.slotID == section.id else { return }

                SongArrangementStore.setTrims(
                    slotID: section.id,
                    trackID: track.id,
                    leading: previewClipTrims.leading,
                    trailing: previewClipTrims.trailing,
                    in: &clipTrims
                )
                onClipTrimCommitted()
            }
    }

    private func resolvedClipRegion(clipID: UUID) -> ClipRegion? {
        if let previewClipRegion,
           previewClipRegion.id == clipID,
           previewClipRegion.trackID == track.id {
            return previewClipRegion
        }
        return ClipRegionStore.region(id: clipID, trackID: track.id, in: clipRegions)
    }

    private func resolvedClipBounds(
        clipID: UUID,
        fallbackStart: TimeInterval,
        fallbackEnd: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval) {
        guard let region = resolvedClipRegion(clipID: clipID) else {
            return (fallbackStart, fallbackEnd)
        }
        return (region.timelineStartSeconds, region.timelineEndSeconds)
    }

    private func isClipRegionTrimActive(
        regionID: UUID,
        edge: ClipRegionStore.RegionTrimEdge
    ) -> Bool {
        activeClipRegionTrim?.regionID == regionID && activeClipRegionTrim?.edge == edge
    }

    private func clipRegionTrimDragGesture(
        for region: ClipRegion,
        edge: ClipRegionStore.RegionTrimEdge,
        boundsStart: TimeInterval,
        boundsEnd: TimeInterval
    ) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(TimelineDragSpace.name))
            .onChanged { value in
                if activeClipRegionTrim?.regionID != region.id || activeClipRegionTrim?.edge != edge {
                    activeClipRegionTrim = (region.id, edge)
                    clipRegionTrimBaseline = ClipRegionStore.region(
                        id: region.id,
                        trackID: track.id,
                        in: clipRegions
                    ) ?? region
                }

                guard let clipRegionTrimBaseline else { return }

                let timelineTime = timelineTime(atContentX: value.location.x)
                let timelineOffset: TimeInterval
                switch edge {
                case .leading:
                    timelineOffset = timelineTime - clipRegionTrimBaseline.timelineStartSeconds
                case .trailing:
                    timelineOffset = timelineTime - clipRegionTrimBaseline.timelineEndSeconds
                }

                previewClipRegion = ClipRegionStore.regionByTrimmingEdge(
                    clipRegionTrimBaseline,
                    edge: edge,
                    timelineOffset: timelineOffset,
                    in: clipRegions,
                    boundsStart: boundsStart,
                    boundsEnd: boundsEnd
                )
            }
            .onEnded { _ in
                defer {
                    activeClipRegionTrim = nil
                    clipRegionTrimBaseline = nil
                    previewClipRegion = nil
                }

                guard let previewClipRegion,
                      let index = clipRegions.firstIndex(where: {
                          $0.id == previewClipRegion.id && $0.trackID == track.id
                      }) else {
                    return
                }

                clipRegions[index] = previewClipRegion
                onClipTrimCommitted()
            }
    }

    private func clipTimelineBounds(for section: ArrangementDisplaySection) -> (start: TimeInterval, end: TimeInterval) {
        if let region = resolvedClipRegion(clipID: section.id) {
            return (region.timelineStartSeconds, region.timelineEndSeconds)
        }

        guard let previewClipTrims, previewClipTrims.slotID == section.id else {
            return (section.timelineStartSeconds, section.timelineEndSeconds)
        }

        return (
            section.columnStartSeconds + previewClipTrims.leading,
            section.columnEndSeconds - previewClipTrims.trailing
        )
    }

    private func isClipTrimActive(sectionID: UUID, edge: ArrangementClipTrimEdge) -> Bool {
        activeClipTrim?.slotID == sectionID && activeClipTrim?.edge == edge
    }

    private func hydratePeaksFromCache() {
        if let cached = WaveformCache.shared.cachedPeaks(for: fileURL) {
            sourcePeaks = cached
        }
    }

    private func applyTrimTime(handle: TrimHandle, time: TimeInterval) {
        let minGap: TimeInterval = 0.1

        switch handle {
        case .start:
            let maxStart = effectiveEnd - minGap
            track.trimStartSeconds = min(max(0, time), maxStart)
        case .end:
            let minEnd = track.trimStartSeconds + minGap
            track.trimEndSeconds = min(max(minEnd, time), fileDuration)
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
            .frame(width: 14)
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
                    NSCursor.resizeLeftRight.push()
                case .ended:
                    isHovering = false
                    NSCursor.pop()
                }
            }
            #else
            .opacity(isEnabled && isActive ? 1 : 0)
            #endif
    }
}
