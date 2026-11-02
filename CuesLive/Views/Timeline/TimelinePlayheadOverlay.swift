import SwiftUI

// MARK: - Playhead metrics

private enum PlayheadMetrics {
    static let handleWidth: CGFloat = 12
    static let handleBodyHeight: CGFloat = 9
    static let handleTipHeight: CGFloat = 5
    static let lineWidth: CGFloat = 1
    static let borderWidth: CGFloat = 1

    static var handleHeight: CGFloat { handleBodyHeight + handleTipHeight }
    static var lineTotalWidth: CGFloat { lineWidth + borderWidth * 2 }
}

// MARK: - Playhead clock

/// Drives playhead position from a single display-linked clock.
struct TimelinePlayheadTimeReader<Content: View>: View {
    @Bindable private var audioEngine = AudioEngineManager.shared
    @ViewBuilder let content: (TimeInterval) -> Content

    var body: some View {
        if audioEngine.isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                content(audioEngine.livePlayheadTime())
            }
        } else {
            content(audioEngine.currentTime)
        }
    }
}

// MARK: - Playhead layer

/// Pins timeline content under a single playhead overlay so the handle and line stay in sync.
/// Timeline content stays outside the display-link clock so the DAW lanes are not rebuilt every frame.
struct TimelinePlayheadLayer<Content: View>: View {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
            TimelinePlayheadTimeReader { playheadTime in
                TimelinePlayheadOverlay(
                    playheadTime: playheadTime,
                    duration: duration,
                    contentWidth: contentWidth,
                    height: height
                )
            }
        }
        .frame(width: displayWidth, alignment: .leading)
    }
}

/// Logic Pro–style playhead drawn in one canvas pass with a shared pixel-aligned center.
struct TimelinePlayheadOverlay: View {
    @Environment(\.displayScale) private var displayScale

    let playheadTime: TimeInterval
    let duration: TimeInterval
    let contentWidth: CGFloat
    let height: CGFloat
    /// When the overlay is pinned to the viewport, subtract the lane horizontal scroll offset.
    var horizontalScrollOffset: CGFloat = 0

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    private var clampedTime: TimeInterval {
        min(max(0, playheadTime), safeDuration)
    }

    var body: some View {
        Canvas { context, size in
            let centerX = pixelAligned(
                TimelineLayout.xPosition(
                    for: clampedTime,
                    duration: safeDuration,
                    contentWidth: contentWidth
                ) - horizontalScrollOffset,
                scale: displayScale
            )
            drawPlayhead(in: context, size: size, centerX: centerX)
        }
        .frame(width: contentWidth, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func drawPlayhead(in context: GraphicsContext, size: CGSize, centerX: CGFloat) {
        drawLine(in: context, size: size, centerX: centerX)
        drawHandle(in: context, centerX: centerX)
    }

    private func drawLine(in context: GraphicsContext, size: CGSize, centerX: CGFloat) {
        let lineTop = PlayheadMetrics.handleHeight
        let lineHeight = max(0, size.height - lineTop)
        guard lineHeight > 0 else { return }

        let lineLeft = pixelAligned(centerX - PlayheadMetrics.lineTotalWidth / 2, scale: displayScale)
        let borderRect = CGRect(
            x: lineLeft,
            y: lineTop,
            width: PlayheadMetrics.lineTotalWidth,
            height: lineHeight
        )
        context.fill(Path(borderRect), with: .color(.dawPlayheadBorder))

        let innerRect = CGRect(
            x: lineLeft + PlayheadMetrics.borderWidth,
            y: lineTop,
            width: PlayheadMetrics.lineWidth,
            height: lineHeight
        )
        context.fill(Path(innerRect), with: .color(.dawPlayheadFill))
    }

    private func drawHandle(in context: GraphicsContext, centerX: CGFloat) {
        let handleLeft = pixelAligned(centerX - PlayheadMetrics.handleWidth / 2, scale: displayScale)
        let handleRect = CGRect(
            x: handleLeft,
            y: 0,
            width: PlayheadMetrics.handleWidth,
            height: PlayheadMetrics.handleHeight
        )
        let handlePath = playheadHandlePath(in: handleRect)

        context.fill(handlePath, with: .color(.dawPlayheadFill))
        context.stroke(
            handlePath,
            with: .color(.dawPlayheadBorder),
            style: StrokeStyle(lineWidth: PlayheadMetrics.borderWidth)
        )
    }

    private func playheadHandlePath(in rect: CGRect) -> Path {
        let bodyBottom = rect.height * (PlayheadMetrics.handleBodyHeight / PlayheadMetrics.handleHeight)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bodyBottom))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bodyBottom))
        path.closeSubpath()
        return path
    }

    private func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value.rounded(.toNearestOrAwayFromZero) }
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }
}

/// Wires section-loop monitoring and playback-time handling into a timeline view.
struct SectionLoopPlaybackSupport: View {
    /// UI / clock engine used for playhead observation. Remains `shared` after overlap.
    @Bindable private var clockEngine = AudioEngineManager.shared
    /// Audible engine that must own the transport loop region. After an overlap
    /// handoff this can be a separate `AudioEngineManager` instance.
    var playbackEngine: AudioEngineManager = .shared
    @Bindable var loopController: SectionLoopController
    let sections: [ArrangementDisplaySection]
    let loopSlotIDs: Set<UUID>
    let onLoopActivated: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                syncEngineLoopRegion()
                installWillReachEndHandler()
            }
            .onDisappear {
                clearLoopRegions()
                clearWillReachEndHandler()
            }
            .onChange(of: clockEngine.currentTime) { _, time in
                loopController.handlePlaybackTimeChange(
                    at: time,
                    sections: sections,
                    loopSlotIDs: loopSlotIDs,
                    onActivate: {
                        onLoopActivated()
                        syncEngineLoopRegion()
                    }
                )
                syncEngineLoopRegion()
            }
            .onChange(of: loopSlotIDs) { _, newLoopSlotIDs in
                loopController.handleLoopSlotIDsChange(newLoopSlotIDs)
                loopController.handlePlaybackTimeChange(
                    at: clockEngine.currentTime,
                    sections: sections,
                    loopSlotIDs: newLoopSlotIDs,
                    onActivate: onLoopActivated
                )
                syncEngineLoopRegion()
                installWillReachEndHandler()
            }
            .onChange(of: sections) { _, _ in
                syncEngineLoopRegion()
                installWillReachEndHandler()
            }
            .onChange(of: loopController.isLooping) { _, _ in
                syncEngineLoopRegion()
            }
            .onChange(of: ObjectIdentifier(playbackEngine)) { _, _ in
                syncEngineLoopRegion()
                installWillReachEndHandler()
            }
    }

    /// Arms the audio-thread loop region. Seeking/snapping is intentionally not
    /// used — wrapping is sample-accurate inside the transport + render path.
    private func syncEngineLoopRegion() {
        if let section = loopController.activeSection(in: sections, loopSlotIDs: loopSlotIDs) {
            applyLoopRegion(
                start: section.timelineStartSeconds,
                end: section.timelineEndSeconds
            )
        } else {
            clearLoopRegions()
        }
    }

    private func applyLoopRegion(start: TimeInterval, end: TimeInterval) {
        playbackEngine.setSectionLoop(start: start, end: end)
        // After overlap, the UI clock stays on `shared` while audio plays on a
        // separate engine — both need the loop region so playhead and audio wrap.
        if playbackEngine !== clockEngine {
            clockEngine.setSectionLoop(start: start, end: end)
        }
    }

    private func clearLoopRegions() {
        playbackEngine.clearSectionLoop()
        if playbackEngine !== clockEngine {
            clockEngine.clearSectionLoop()
        }
    }

    private func installWillReachEndHandler() {
        let handler: () -> Bool = { [loopController, sections, loopSlotIDs, onLoopActivated, playbackEngine, clockEngine] in
            // Activate a marked loop section if playback reached the end before the
            // deferred SwiftUI time observer ran (common for single-section songs).
            let duration = max(playbackEngine.duration, clockEngine.duration)
            let sampleRate = playbackEngine.referenceSampleRate
            let nearEnd = max(
                0,
                duration - SectionLoopTiming.sampleThreshold(sampleRate: sampleRate)
            )
            loopController.handlePlaybackTimeChange(
                at: nearEnd,
                sections: sections,
                loopSlotIDs: loopSlotIDs,
                onActivate: onLoopActivated
            )

            guard let section = loopController.activeSection(
                in: sections,
                loopSlotIDs: loopSlotIDs
            ) else {
                return playbackEngine.hasActiveSectionLoop || clockEngine.hasActiveSectionLoop
            }

            playbackEngine.setSectionLoop(
                start: section.timelineStartSeconds,
                end: section.timelineEndSeconds
            )
            if playbackEngine !== clockEngine {
                clockEngine.setSectionLoop(
                    start: section.timelineStartSeconds,
                    end: section.timelineEndSeconds
                )
            }
            return true
        }

        playbackEngine.onWillReachEnd = handler
        if playbackEngine !== clockEngine {
            clockEngine.onWillReachEnd = handler
        }
    }

    private func clearWillReachEndHandler() {
        playbackEngine.onWillReachEnd = nil
        if playbackEngine !== clockEngine {
            clockEngine.onWillReachEnd = nil
        }
    }
}

/// Fires a callback when playback reaches a scheduled section-cue time.
struct SectionCueMonitor: View {
    @Bindable private var audioEngine = AudioEngineManager.shared
    let cuedSectionID: UUID?
    let cueFireTime: TimeInterval?
    let onFire: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: audioEngine.currentTime) { _, time in
                guard cueFireTime != nil, cuedSectionID != nil else { return }
                guard time >= cueFireTime! else { return }
                onFire()
            }
    }
}

/// Speaks the upcoming section name one measure before its boundary.
struct SectionAnnounceMonitor: View {
    @Bindable private var audioEngine = AudioEngineManager.shared
    let enabled: Bool
    let sections: [ArrangementDisplaySection]
    let cuedSectionID: UUID?
    let cueFireTime: TimeInterval?
    let announcer: SectionAnnouncer

    @State private var lastAnnouncedBoundary: TimeInterval?
    @State private var lastSeenTime: TimeInterval = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: audioEngine.currentTime) { _, time in
                evaluate(at: time)
            }
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled {
                    resetTracking()
                } else {
                    evaluate(at: audioEngine.currentTime)
                }
            }
            .onChange(of: cuedSectionID) { _, _ in
                handleManualCueChange()
            }
            .onChange(of: cueFireTime) { _, _ in
                handleManualCueChange()
            }
            .onChange(of: audioEngine.isPlaying) { _, isPlaying in
                if !isPlaying {
                    resetTracking()
                } else {
                    evaluate(at: audioEngine.currentTime)
                }
            }
    }

    private func resetTracking() {
        lastAnnouncedBoundary = nil
        lastSeenTime = audioEngine.currentTime
    }

    /// When the user cues a section, only schedule a spoken call if a full measure
    /// of lead time remains. Cueing inside that final measure skips a late call.
    private func handleManualCueChange() {
        lastSeenTime = audioEngine.currentTime
        lastAnnouncedBoundary = nil

        guard enabled,
              audioEngine.isPlaying,
              let cueFireTime,
              cuedSectionID != nil else {
            return
        }

        let lead = audioEngine.measureLeadDuration(endingAt: cueFireTime)
        let announceAt = max(0, cueFireTime - lead)
        if audioEngine.currentTime + 0.001 >= announceAt {
            // Not enough runway for a true one-measure-early call.
            lastAnnouncedBoundary = cueFireTime
            return
        }

        evaluate(at: audioEngine.currentTime)
    }

    private func evaluate(at time: TimeInterval) {
        defer { lastSeenTime = time }

        guard enabled, audioEngine.isPlaying else { return }

        // Detect seeks / backward jumps so the same boundary can announce again.
        if time + 0.05 < lastSeenTime {
            lastAnnouncedBoundary = nil
        }

        guard let target = nextAnnouncementTarget(at: time) else { return }

        let lead = audioEngine.measureLeadDuration(endingAt: target.boundary)
        let announceAt = max(0, target.boundary - lead)

        guard time >= announceAt else { return }
        guard lastAnnouncedBoundary != target.boundary else { return }

        // Manual cues only speak when we reach the one-measure mark with time to spare.
        // If we somehow evaluate after the boundary, skip rather than calling late.
        if target.isManualCue, time + 0.001 >= target.boundary {
            lastAnnouncedBoundary = target.boundary
            return
        }

        lastAnnouncedBoundary = target.boundary
        announcer.announce(name: target.name)
    }

    private func nextAnnouncementTarget(
        at time: TimeInterval
    ) -> (name: String, boundary: TimeInterval, isManualCue: Bool)? {
        if let cuedSectionID,
           let cueFireTime,
           cueFireTime > time + 0.001,
           let section = sections.first(where: { $0.id == cuedSectionID }) {
            return (section.name, cueFireTime, true)
        }

        guard let next = sections.first(where: { $0.timelineStartSeconds > time + 0.001 }) else {
            return nil
        }
        return (next.name, next.timelineStartSeconds, false)
    }
}