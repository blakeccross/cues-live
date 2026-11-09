import SwiftUI

struct SetlistOverlapEditorContext: Identifiable {
    let id: String
    let entry: SetlistEntry
    let outgoingSong: Song
    let incomingSong: Song
    let initialStartOffset: TimeInterval
    let outgoingSnapshot: LiveSongWaveformSnapshot?
    let incomingSnapshot: LiveSongWaveformSnapshot?

    init(
        entry: SetlistEntry,
        outgoingSong: Song,
        incomingSong: Song,
        outgoingSnapshot: LiveSongWaveformSnapshot? = nil,
        incomingSnapshot: LiveSongWaveformSnapshot? = nil
    ) {
        self.id = "\(outgoingSong.id.uuidString)-\(incomingSong.id.uuidString)"
        self.entry = entry
        self.outgoingSong = outgoingSong
        self.incomingSong = incomingSong
        self.initialStartOffset = entry.overlapConfig?.startOffsetSeconds ?? 0
        self.outgoingSnapshot = outgoingSnapshot
        self.incomingSnapshot = incomingSnapshot
    }
}

struct SetlistOverlapEditorView: View {
    let context: SetlistOverlapEditorContext
    let onCommit: (OverlapTransitionConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var windowZoom: CGFloat
    @State private var pinchStartZoom: CGFloat?
    @State private var startOffsetSeconds: TimeInterval
    @State private var dragStartOffset: TimeInterval?
    @State private var previewEngine = OverlapPreviewEngine()
    @State private var isLoadingPreview = false
    @State private var previewError: String?
    @State private var outgoingSnapshot: LiveSongWaveformSnapshot?
    @State private var incomingSnapshot: LiveSongWaveformSnapshot?
    @State private var isLoadingWaveforms = true
    @State private var outgoingPeaks: [Float] = []
    @State private var incomingPeaks: [Float] = []
    @State private var wasLivePlaybackRunning = false

    private let laneHeight: CGFloat = 88
    private static let minimumWindowZoomFloor: CGFloat = 0.25
    private static let zoomAdjustmentStep: CGFloat = 0.15

    private var waveformStackHeight: CGFloat {
        laneHeight * 2 + AppSpacing.sm
    }

    private var waveformEditorHeight: CGFloat {
        waveformStackHeight + AppSpacing.sm * 2
    }

    private var baseWindowDuration: TimeInterval {
        OverlapTransitionTiming.defaultEditorWindowDuration
    }

    private var minimumWindowZoom: CGFloat {
        guard baseWindowDuration > 0 else { return Self.minimumWindowZoomFloor }
        let overlapLimitedZoom = CGFloat(startOffsetSeconds / baseWindowDuration)
        return max(Self.minimumWindowZoomFloor, min(1, overlapLimitedZoom))
    }

    private var maximumWindowZoom: CGFloat {
        guard baseWindowDuration > 0 else { return 1 }
        let incomingDuration = incomingSnapshot?.timelineDuration ?? 0
        let maxDuration = max(outgoingDuration, incomingDuration)
        return max(1, CGFloat(maxDuration / baseWindowDuration))
    }

    private var windowDuration: TimeInterval {
        guard baseWindowDuration > 0 else { return 0 }
        let zoom = Self.clampedWindowZoom(
            windowZoom,
            maximum: maximumWindowZoom,
            minimum: minimumWindowZoom
        )
        return baseWindowDuration * TimeInterval(zoom)
    }

    private var outgoingDuration: TimeInterval {
        outgoingSnapshot?.timelineDuration ?? 0
    }

    private var incomingLaneOffset: TimeInterval {
        OverlapTransitionTiming.incomingLaneOffset(
            outgoingDuration: outgoingDuration,
            windowDuration: windowDuration,
            startOffsetSeconds: startOffsetSeconds
        )
    }

    private var scrollAnchor: OverlapEditorScrollAnchor {
        OverlapEditorScrollAnchor(
            isLoadingWaveforms: isLoadingWaveforms,
            windowZoom: windowZoom,
            startOffsetSeconds: startOffsetSeconds
        )
    }

    init(
        context: SetlistOverlapEditorContext,
        onCommit: @escaping (OverlapTransitionConfig) -> Void
    ) {
        self.context = context
        self.onCommit = onCommit

        _windowZoom = State(initialValue: 1)
        _startOffsetSeconds = State(initialValue: context.initialStartOffset)
        _outgoingSnapshot = State(initialValue: context.outgoingSnapshot)
        _incomingSnapshot = State(initialValue: context.incomingSnapshot)
        _isLoadingWaveforms = State(
            initialValue: context.outgoingSnapshot == nil || context.incomingSnapshot == nil
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.md) {
                editorHeader
                waveformEditor
                controlsRow

                if let previewError {
                    Text(previewError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(AppSpacing.lg)
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Overlap")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commit()
                    }
                    .disabled(!configIsValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 420)
        #endif
        .onDisappear {
            previewEngine.teardown()
            restoreLivePlaybackIfNeeded()
        }
        .onChange(of: previewEngine.isPlaying) { _, isPlaying in
            if !isPlaying {
                restoreLivePlaybackIfNeeded()
            }
        }
        .task {
            await loadWaveformSnapshotsIfNeeded()
        }
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(context.outgoingSong.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text("into \(context.incomingSong.name)")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waveformEditor: some View {
        Group {
            if isLoadingWaveforms {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .fill(AppColors.surface)
                    ProgressView("Loading waveforms…")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(height: waveformEditorHeight)
            } else {
                waveformEditorContent
            }
        }
    }

    private var waveformEditorContent: some View {
        GeometryReader { geometry in
            let viewportWidth = max(geometry.size.width, 1)
            let incomingLaneStartX = TimelineLayout.xPosition(
                for: incomingLaneOffset,
                duration: max(windowDuration, 0.001),
                contentWidth: viewportWidth
            )
            let incomingLaneEndX = incomingLaneStartX + viewportWidth
            let scrollWidth = scrollContentWidth(
                viewportWidth: viewportWidth,
                incomingLaneEndX: incomingLaneEndX
            )

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: AppSpacing.sm) {
                            waveformRow(
                                snapshot: outgoingSnapshot,
                                sourcePeaks: outgoingPeaks,
                                timeRange: outgoingWindowRange,
                                laneOffset: 0,
                                isDraggable: false,
                                viewportWidth: viewportWidth,
                                rowWidth: scrollWidth
                            )

                            waveformRow(
                                snapshot: incomingSnapshot,
                                sourcePeaks: incomingPeaks,
                                timeRange: incomingWindowRange,
                                laneOffset: incomingLaneOffset,
                                isDraggable: true,
                                viewportWidth: viewportWidth,
                                rowWidth: scrollWidth
                            )
                        }
                        .padding(AppSpacing.sm)

                        if previewEngine.isPlaying || previewEngine.currentTime > 0 {
                            overlapPlayhead(contentWidth: viewportWidth)
                        }

                        Color.clear
                            .frame(width: 1, height: 1)
                            .offset(x: AppSpacing.sm)
                            .id("timelineStart")

                        Color.clear
                            .frame(width: 1, height: 1)
                            .offset(x: AppSpacing.sm + incomingLaneEndX)
                            .id("incomingTrailing")
                    }
                    .frame(width: scrollWidth, height: waveformEditorHeight, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .simultaneousGesture(pinchZoomGesture)
                .onAppear {
                    scrollToShowLanes(
                        proxy: proxy,
                        viewportWidth: viewportWidth,
                        incomingLaneEndX: incomingLaneEndX
                    )
                }
                .onChange(of: scrollAnchor) {
                    guard !isLoadingWaveforms else { return }
                    scrollToShowLanes(
                        proxy: proxy,
                        viewportWidth: viewportWidth,
                        incomingLaneEndX: incomingLaneEndX
                    )
                }
            }
        }
        .frame(height: waveformEditorHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColors.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setWindowZoom(windowZoom + Self.zoomAdjustmentStep)
            case .decrement:
                setWindowZoom(windowZoom - Self.zoomAdjustmentStep)
            @unknown default:
                break
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: AppSpacing.md) {
            Spacer()

            Button {
                Task { await togglePreview() }
            } label: {
                if isLoadingPreview {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        previewEngine.isPlaying ? "Stop" : "Preview",
                        systemImage: previewEngine.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }
            }
            .disabled(windowDuration <= 0 || isLoadingPreview)
        }
        .foregroundStyle(AppColors.textPrimary)
    }

    private func scrollContentWidth(viewportWidth: CGFloat, incomingLaneEndX: CGFloat) -> CGFloat {
        let lanePadding = AppSpacing.sm * 2
        return max(viewportWidth, lanePadding + incomingLaneEndX)
    }

    private func scrollToShowLanes(
        proxy: ScrollViewProxy,
        viewportWidth: CGFloat,
        incomingLaneEndX: CGFloat
    ) {
        let paddedIncomingEndX = AppSpacing.sm + incomingLaneEndX
        if paddedIncomingEndX > viewportWidth {
            proxy.scrollTo("incomingTrailing", anchor: .trailing)
        } else {
            proxy.scrollTo("timelineStart", anchor: .leading)
        }
    }

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
                    windowZoom = Self.clampedWindowZoom(
                        pinchStartZoom / scale,
                        maximum: maximumWindowZoom,
                        minimum: minimumWindowZoom
                    )
                }
            }
            .onEnded { _ in
                pinchStartZoom = nil
                invalidatePreviewConfiguration()
            }
    }

    private func setWindowZoom(_ proposed: CGFloat) {
        let clamped = Self.clampedWindowZoom(
            proposed,
            maximum: maximumWindowZoom,
            minimum: minimumWindowZoom
        )
        guard clamped != windowZoom else { return }
        windowZoom = clamped
        invalidatePreviewConfiguration()
    }

    private static func clampedWindowZoom(_ zoom: CGFloat, maximum: CGFloat, minimum: CGFloat) -> CGFloat {
        min(maximum, max(minimum, zoom))
    }

    private func loadWaveformSnapshotsIfNeeded() async {
        if outgoingSnapshot == nil || incomingSnapshot == nil {
            isLoadingWaveforms = true
            await Task.yield()
        }

        if outgoingSnapshot == nil {
            outgoingSnapshot = context.outgoingSnapshot
                ?? PlaybackCoordinator.makeWaveformSnapshot(for: context.outgoingSong)
        }
        if incomingSnapshot == nil {
            incomingSnapshot = context.incomingSnapshot
                ?? PlaybackCoordinator.makeWaveformSnapshot(for: context.incomingSong)
        }

        applyDefaultStartOffsetIfNeeded()
        await loadWaveformPeaks()
        isLoadingWaveforms = false
    }

    private func loadWaveformPeaks() async {
        if let outgoingSnapshot, !outgoingSnapshot.trackSources.isEmpty {
            outgoingPeaks = await WaveformCache.shared.summedPeaks(for: outgoingSnapshot.trackSources)
        }
        if let incomingSnapshot, !incomingSnapshot.trackSources.isEmpty {
            incomingPeaks = await WaveformCache.shared.summedPeaks(for: incomingSnapshot.trackSources)
        }
    }

    private func applyDefaultStartOffsetIfNeeded() {
        guard context.initialStartOffset <= 0,
              startOffsetSeconds <= 0,
              let outgoingSnapshot else {
            return
        }

        startOffsetSeconds = OverlapTransitionTiming.defaultStartOffset(
            windowDuration: baseWindowDuration,
            outgoingDuration: outgoingSnapshot.timelineDuration
        )
    }

    private var outgoingWindowRange: ClosedRange<TimeInterval> {
        let end = outgoingDuration
        let start = max(0, end - windowDuration)
        return start...end
    }

    private var incomingWindowRange: ClosedRange<TimeInterval> {
        0...max(windowDuration, 0.001)
    }

    @ViewBuilder
    private func waveformRow(
        snapshot: LiveSongWaveformSnapshot?,
        sourcePeaks: [Float],
        timeRange: ClosedRange<TimeInterval>,
        laneOffset: TimeInterval,
        isDraggable: Bool,
        viewportWidth: CGFloat,
        rowWidth: CGFloat
    ) -> some View {
        let xOffset = TimelineLayout.xPosition(
            for: laneOffset,
            duration: max(windowDuration, 0.001),
            contentWidth: viewportWidth
        )

        ZStack(alignment: .leading) {
            if let snapshot {
                let lane = OverlapWaveformLaneView(
                    snapshot: snapshot,
                    sourcePeaks: sourcePeaks,
                    timeRange: timeRange,
                    contentWidth: viewportWidth,
                    playheadTime: previewPlayheadTime(in: timeRange, laneOffset: laneOffset),
                    height: laneHeight,
                    useLinearPeakMapping: laneOffset > 0
                )
                .frame(width: viewportWidth, height: laneHeight)
                .offset(x: xOffset)
                .contentShape(Rectangle())

                if isDraggable {
                    lane.highPriorityGesture(dragGesture(contentWidth: viewportWidth))
                } else {
                    lane
                }
            } else {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColors.backgroundSecondary)
                    .frame(width: viewportWidth, height: laneHeight)
                    .offset(x: xOffset)
                    .overlay {
                        Text("No waveform")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
            }
        }
        .frame(width: rowWidth, height: laneHeight, alignment: .leading)
    }

    private func dragGesture(contentWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = startOffsetSeconds
                }
                guard let dragStartOffset, windowDuration > 0 else { return }
                let deltaTime = TimeInterval(value.translation.width / contentWidth) * windowDuration
                let outgoingWindowStart = max(0, outgoingDuration - windowDuration)
                let startAlignment = outgoingDuration - dragStartOffset
                let newAlignment = startAlignment + deltaTime
                let newLaneOffset = newAlignment - outgoingWindowStart
                startOffsetSeconds = OverlapTransitionTiming.startOffset(
                    outgoingDuration: outgoingDuration,
                    windowDuration: windowDuration,
                    incomingLaneOffset: newLaneOffset
                )
            }
            .onEnded { _ in
                dragStartOffset = nil
                invalidatePreviewConfiguration()
            }
    }

    private func overlapPlayhead(contentWidth: CGFloat) -> some View {
        TimelinePlayheadOverlay(
            playheadTime: previewEngine.currentTime,
            duration: max(windowDuration, 0.001),
            contentWidth: contentWidth,
            height: waveformStackHeight + AppSpacing.sm * 2
        )
        .offset(x: AppSpacing.sm, y: AppSpacing.sm)
    }

    private func previewPlayheadTime(
        in timeRange: ClosedRange<TimeInterval>,
        laneOffset: TimeInterval
    ) -> TimeInterval? {
        guard previewEngine.isPlaying || previewEngine.currentTime > 0 else { return nil }
        let previewTime = previewEngine.currentTime
        if laneOffset > 0 {
            let local = previewTime - laneOffset
            guard local >= 0 else { return nil }
            return timeRange.lowerBound + local
        }
        return timeRange.lowerBound + previewTime
    }

    private var configIsValid: Bool {
        OverlapTransitionConfig(startOffsetSeconds: startOffsetSeconds).isValid && windowDuration > 0
    }

    private func commit() {
        let config = OverlapTransitionConfig(startOffsetSeconds: startOffsetSeconds)
        previewEngine.teardown()
        onCommit(config)
        dismiss()
    }

    private func invalidatePreviewConfiguration() {
        if previewEngine.isPlaying {
            previewEngine.pause()
            restoreLivePlaybackIfNeeded()
        }
        previewEngine.invalidateConfiguration()
    }

    private func togglePreview() async {
        if previewEngine.isPlaying {
            previewEngine.pause()
            return
        }

        pauseLivePlaybackForPreview()
        await loadPreview()
        guard previewEngine.isLoaded else {
            previewError = previewEngine.loadError ?? "Unable to load overlap preview."
            restoreLivePlaybackIfNeeded()
            return
        }

        previewEngine.play()
        previewError = previewEngine.loadError
        if previewEngine.loadError != nil || !previewEngine.isPlaying {
            if !previewEngine.isPlaying, previewError == nil {
                previewError = "Unable to start overlap preview."
            }
            restoreLivePlaybackIfNeeded()
        }
    }

    private func pauseLivePlaybackForPreview() {
        let audioEngine = AudioEngineManager.shared
        wasLivePlaybackRunning = audioEngine.isPlaying
        if wasLivePlaybackRunning {
            audioEngine.pause()
        }
        audioEngine.suspendHardware()
    }

    private func restoreLivePlaybackIfNeeded() {
        AudioEngineManager.shared.resumeHardware()
        if wasLivePlaybackRunning {
            AudioEngineManager.shared.play()
            wasLivePlaybackRunning = false
        }
    }

    private func loadPreview() async {
        isLoadingPreview = true
        previewError = nil
        defer { isLoadingPreview = false }

        await previewEngine.load(
            outgoingSong: context.outgoingSong,
            incomingSong: context.incomingSong,
            startOffsetSeconds: startOffsetSeconds,
            windowDuration: windowDuration
        )
        previewError = previewEngine.loadError
    }
}

private struct OverlapEditorScrollAnchor: Equatable {
    let isLoadingWaveforms: Bool
    let windowZoom: CGFloat
    let startOffsetSeconds: TimeInterval
}

private struct OverlapWaveformLaneView: View {
    let snapshot: LiveSongWaveformSnapshot
    let sourcePeaks: [Float]
    let timeRange: ClosedRange<TimeInterval>
    let contentWidth: CGFloat
    let playheadTime: TimeInterval?
    let height: CGFloat
    let useLinearPeakMapping: Bool

    private var rangeDuration: TimeInterval {
        max(0.001, timeRange.upperBound - timeRange.lowerBound)
    }

    private var displayPeaks: [Float] {
        WaveformPeakResampler.displayPeaks(
            from: sourcePeaks,
            fileDuration: snapshot.fileDuration,
            clips: useLinearPeakMapping ? [] : snapshot.peakClips,
            timelineDuration: snapshot.timelineDuration,
            timeRange: timeRange,
            contentWidth: max(contentWidth, 120),
            minimumBarSlotWidth: WaveformPeakResampler.voiceMemosBarSlotWidth
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color.liveVoiceMemosBackground)

            if sourcePeaks.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else if displayPeaks.isEmpty {
                Text("No waveform")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                WaveformBarsCanvas(
                    bars: displayPeaks,
                    showsEmptyBaseline: false,
                    style: .voiceMemosBars,
                    playheadFraction: playheadFraction,
                    playedColor: .white.opacity(LiveSetlistWaveformMetrics.waveformPlayedOpacity),
                    unplayedColor: .white.opacity(LiveSetlistWaveformMetrics.waveformUnplayedOpacity)
                )
                .frame(width: max(contentWidth, 1), height: height)
                .padding(.vertical, 2)
            }
        }
        .frame(width: max(contentWidth, 1), height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    private var playheadFraction: CGFloat? {
        guard let playheadTime, contentWidth > 0 else { return nil }
        let clamped = min(max(playheadTime, timeRange.lowerBound), timeRange.upperBound)
        let fraction = (clamped - timeRange.lowerBound) / rangeDuration
        return CGFloat(fraction)
    }
}
