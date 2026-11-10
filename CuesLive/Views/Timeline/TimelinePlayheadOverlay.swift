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

enum TimelinePlayheadStyle {
    /// Triangle handle and gray line.
    case handle
    /// Full-height red line, drawn only while playing.
    case line
}

/// Playhead drawn in one canvas pass with a shared pixel-aligned center.
struct TimelinePlayheadOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    let playheadTime: TimeInterval
    let duration: TimeInterval
    let contentWidth: CGFloat
    let height: CGFloat
    var style: TimelinePlayheadStyle = .handle
    /// When the overlay is pinned to the viewport, subtract the lane horizontal scroll offset.
    var horizontalScrollOffset: CGFloat = 0
    /// Width of a pinned overlay. The playhead is still positioned in timeline coordinates.
    var canvasWidth: CGFloat? = nil

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
        .frame(width: canvasWidth ?? contentWidth, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func drawPlayhead(in context: GraphicsContext, size: CGSize, centerX: CGFloat) {
        switch style {
        case .handle:
            drawLine(in: context, size: size, centerX: centerX)
            drawHandle(in: context, centerX: centerX)
        case .line:
            var path = Path()
            path.move(to: CGPoint(x: centerX, y: 0))
            path.addLine(to: CGPoint(x: centerX, y: size.height))
            context.stroke(
                path,
                with: .color(.soundcraftPlayhead(colorScheme: colorScheme)),
                style: StrokeStyle(lineWidth: 1.5)
            )
        }
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

/// Blinking insertion on the selected lanes. Visible while stopped, until playback starts.
struct TimelineInsertionCursor: View {
    @Environment(\.colorScheme) private var colorScheme

    let time: TimeInterval
    let duration: TimeInterval
    let contentWidth: CGFloat
    let rows: [Int]
    let laneHeight: CGFloat
    let rowStride: CGFloat
    let areaHeight: CGFloat

    @State private var anchor = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { context in
            let elapsed = context.date.timeIntervalSince(anchor)
            let visible = Int(elapsed * 2) % 2 == 0
            Canvas { canvas, _ in
                guard visible else { return }
                let x = TimelineLayout.xPosition(
                    for: min(max(0, time), max(duration, 0.001)),
                    duration: max(duration, 0.001),
                    contentWidth: contentWidth
                )
                let color = Color.soundcraftInsertion(colorScheme: colorScheme)
                for row in rows {
                    var path = Path()
                    let y = CGFloat(row) * rowStride
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + laneHeight))
                    canvas.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1))
                }
            }
            .frame(width: contentWidth, height: areaHeight, alignment: .topLeading)
        }
        .onChange(of: time) { _, _ in
            anchor = Date()
        }
        .onChange(of: rows) { _, _ in
            anchor = Date()
        }
        .allowsHitTesting(false)
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
    let sections: [SongSection]
    let loopSectionIDs: Set<UUID>
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
                    loopSectionIDs: loopSectionIDs,
                    onActivate: {
                        onLoopActivated()
                        syncEngineLoopRegion()
                    }
                )
                syncEngineLoopRegion()
            }
            .onChange(of: loopSectionIDs) { _, newLoopSectionIDs in
                loopController.handleLoopSectionIDsChange(newLoopSectionIDs)
                loopController.handlePlaybackTimeChange(
                    at: clockEngine.currentTime,
                    sections: sections,
                    loopSectionIDs: newLoopSectionIDs,
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
        if let section = loopController.activeSection(in: sections, loopSectionIDs: loopSectionIDs) {
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
        let handler: () -> Bool = { [loopController, sections, loopSectionIDs, onLoopActivated, playbackEngine, clockEngine] in
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
                loopSectionIDs: loopSectionIDs,
                onActivate: onLoopActivated
            )

            guard let section = loopController.activeSection(
                in: sections,
                loopSectionIDs: loopSectionIDs
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
            // A jump to an earlier section never lets the playhead reach the fire time again
            // soon, so the engine reports the jump itself.
            .onChange(of: audioEngine.scheduledTransitionCompletions) { _, _ in
                guard cueFireTime != nil, cuedSectionID != nil else { return }
                onFire()
            }
    }
}

/// Smart Guide: speaks the upcoming section name one measure before its boundary,
/// or the looping section's own name one measure before each wrap.
struct SectionAnnounceMonitor: View {
    @Bindable private var audioEngine = AudioEngineManager.shared
    let enabled: Bool
    let sections: [SongSection]
    let cuedSectionID: UUID?
    let cueFireTime: TimeInterval?
    let loopSection: SongSection?
    let announcer: SectionAnnouncer

    @State private var planner = SmartGuideCallPlanner()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: audioEngine.currentTime) { _, time in
                evaluate(at: time)
            }
            .onChange(of: enabled) { _, isEnabled in
                resetTracking()
                if isEnabled {
                    evaluate(at: audioEngine.currentTime)
                }
            }
            .onChange(of: cuedSectionID) { _, _ in
                evaluate(at: audioEngine.currentTime)
            }
            .onChange(of: cueFireTime) { _, _ in
                evaluate(at: audioEngine.currentTime)
            }
            .onChange(of: loopSection) { _, _ in
                evaluate(at: audioEngine.currentTime)
            }
            .onChange(of: audioEngine.isPlaying) { _, isPlaying in
                resetTracking()
                if isPlaying {
                    evaluate(at: audioEngine.currentTime)
                }
            }
    }

    private func resetTracking() {
        planner.reset(at: audioEngine.currentTime)
    }

    /// Calls only fire when playback crosses the one-measure mark. A cue queued, a loop engaged,
    /// or a seek landing inside that final measure is too late for a call and stays silent.
    private func evaluate(at time: TimeInterval) {
        guard enabled, audioEngine.isPlaying else { return }

        let call = planner.evaluate(
            at: time,
            sections: sections,
            cue: queuedCue,
            loop: loopSection,
            leadDuration: { audioEngine.measureLeadDuration(endingAt: $0) }
        )
        if let call {
            announcer.announce(name: call.name)
        }
    }

    private var queuedCue: SmartGuideCallPlanner.Cue? {
        guard let cuedSectionID,
              let cueFireTime,
              let section = sections.first(where: { $0.id == cuedSectionID }) else {
            return nil
        }
        return SmartGuideCallPlanner.Cue(name: section.name, fireTime: cueFireTime)
    }
}
