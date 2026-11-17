import SwiftUI

/// Sheet for setting how early the next song enters over the end of the current one. The incoming
/// lane drags against the outgoing lane.
@MainActor
struct SetlistOverlapEditorView: View {
    let context: SetlistOverlapEditorContext
    let onCommit: (OverlapTransitionConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State var windowZoom: CGFloat
    @State var pinchStartZoom: CGFloat?
    @State var startOffsetSeconds: TimeInterval
    @State var dragStartOffset: TimeInterval?
    @State var previewEngine = OverlapPreviewEngine()
    @State var isLoadingPreview = false
    @State var previewError: String?
    @State var outgoingSnapshot: LiveSongWaveformSnapshot?
    @State var incomingSnapshot: LiveSongWaveformSnapshot?
    @State var isLoadingWaveforms = true
    @State var wasLivePlaybackRunning = false
    /// Editor time the scrubber is set to. The preview starts here.
    @State var seekTime: TimeInterval = 0
    @State var isScrubbing = false
    /// The stretch of the timeline the editor shows and the scrubber spans. Held still while the
    /// incoming lane is dragged, and recomputed when the drag ends.
    @State var focusRange: ClosedRange<TimeInterval> = 0...0
    /// Editor time to scroll to the leading edge, so the view stays put when `focusRange` changes.
    @State var pendingLeadingTime: TimeInterval?
    /// Bumped when the editor should scroll the transition to the center, such as once the
    /// songs have loaded and the default overlap is applied.
    @State var transitionCenterRequest = 0
    /// How far the lanes are scrolled, in points.
    @State var scrollOffset: CGFloat = 0
    /// Width of the visible lanes, in points.
    @State var viewportWidth: CGFloat = 0

    static let laneHeight: CGFloat = 132
    /// Gap between the outgoing and incoming lanes.
    static let laneSpacing: CGFloat = AppSpacing.xxs
    /// Each zoom button press scales the visible window by this factor.
    static let zoomButtonFactor: CGFloat = 1.5
    /// Seconds shown before the incoming song enters and after the outgoing song ends.
    static let focusMargin: TimeInterval = 10
    /// The scrubber starts this many seconds before the incoming song enters.
    static let previewLeadIn: TimeInterval = 5
    /// A preview started this close to the end restarts from the lead-in instead.
    static let restartTolerance: TimeInterval = 0.25
    /// The closest zoom shows a quarter of the default window.
    static let minimumWindowZoom: CGFloat = 0.25
    private static let previewButtonMinWidth: CGFloat = 96
    #if os(macOS)
    private static let minimumSheetSize = CGSize(width: 620, height: 400)
    #endif

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
        AppSheetContainer {
            NavigationStack {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    VStack(spacing: AppSpacing.xs) {
                        waveformEditor
                        scrubber
                    }
                    controlBar

                    if let previewError {
                        Label(previewError, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.error)
                    }
                }
                .padding(AppSpacing.lg)
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Overlap Transition")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
            }
        }
        #if os(macOS)
        .frame(minWidth: Self.minimumSheetSize.width, minHeight: Self.minimumSheetSize.height)
        #endif
        .onDisappear {
            previewEngine.teardown()
            restoreLivePlaybackIfNeeded()
        }
        .onChange(of: previewEngine.isPlaying) { _, isPlaying in
            if !isPlaying {
                if let playheadTime = previewEngine.playheadTime {
                    seekTime = playheadTime
                }
                restoreLivePlaybackIfNeeded()
            }
        }
        .task {
            await loadWaveformSnapshotsIfNeeded()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                commit()
            }
            .disabled(!configIsValid)
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: AppSpacing.sm) {
            previewButton

            Label("Drag the lower lane to set where it comes in", systemImage: "hand.draw")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .lineLimit(2)

            Spacer(minLength: AppSpacing.sm)

            zoomButton("Zoom Out", systemImage: "minus.magnifyingglass", isEnabled: canZoomOut, action: zoomOut)
            zoomButton("Zoom In", systemImage: "plus.magnifyingglass", isEnabled: canZoomIn, action: zoomIn)
        }
    }

    private var scrubber: some View {
        AppScrubber(
            value: Binding(
                get: { playheadPosition - focusRange.lowerBound },
                set: { seekTime = focusRange.lowerBound + $0 }
            ),
            duration: focusRange.upperBound - focusRange.lowerBound,
            onEditingChanged: { isEditing in
                isScrubbing = isEditing
                if !isEditing {
                    previewEngine.seek(to: seekTime)
                }
            }
        )
        .disabled(isLoadingWaveforms)
    }

    private var previewButton: some View {
        Button {
            Task { await togglePreview() }
        } label: {
            Group {
                if isLoadingPreview {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        previewEngine.isPlaying ? "Stop" : "Preview",
                        systemImage: previewEngine.isPlaying ? "stop.fill" : "play.fill"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(minWidth: Self.previewButtonMinWidth)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(windowDuration <= 0 || isLoadingPreview || isLoadingWaveforms)
    }

    private func zoomButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .help(title)
        .disabled(!isEnabled || isLoadingWaveforms)
    }

    // MARK: - Timing

    var timeline: OverlapEditorTimeline {
        OverlapEditorTimeline(
            outgoingRange: Self.range(of: outgoingSnapshot),
            incomingRange: Self.range(of: incomingSnapshot),
            startOffsetSeconds: startOffsetSeconds
        )
    }

    private static func range(of snapshot: LiveSongWaveformSnapshot?) -> ClosedRange<TimeInterval> {
        guard let window = snapshot?.window else { return 0...0 }
        return window.start...window.end
    }

    var baseWindowDuration: TimeInterval {
        OverlapTransitionTiming.defaultEditorWindowDuration
    }

    /// Zoomed all the way out, the whole focus range fits across the editor.
    var maximumWindowZoom: CGFloat {
        guard baseWindowDuration > 0 else { return 1 }
        return CGFloat((focusRange.upperBound - focusRange.lowerBound) / baseWindowDuration)
    }

    func clampedWindowZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumWindowZoom, max(Self.minimumWindowZoom, zoom))
    }

    /// Seconds shown across the editor's width.
    var windowDuration: TimeInterval {
        guard baseWindowDuration > 0 else { return 0 }
        return baseWindowDuration * TimeInterval(clampedWindowZoom(windowZoom))
    }

    var pointsPerSecond: CGFloat {
        viewportWidth / CGFloat(max(windowDuration, 0.001))
    }

    /// Where the playhead shows: the running preview's position, or the scrubber's while it is
    /// dragged or the preview is stopped.
    var playheadPosition: TimeInterval {
        let position = previewEngine.isPlaying && !isScrubbing ? previewEngine.playheadTime ?? seekTime : seekTime
        return min(max(position, focusRange.lowerBound), focusRange.upperBound)
    }

    /// A few seconds before the incoming song enters.
    var defaultSeekTime: TimeInterval {
        max(focusRange.lowerBound, timeline.incomingEntry - Self.previewLeadIn)
    }

    /// Recomputes the focus range around the current overlap.
    func updateFocusRange() {
        focusRange = timeline.focusRange(margin: Self.focusMargin)
        windowZoom = clampedWindowZoom(windowZoom)
    }

    private var configIsValid: Bool {
        OverlapTransitionConfig(startOffsetSeconds: startOffsetSeconds).isValid && timeline.outgoingLength > 0
    }

    private func commit() {
        previewEngine.teardown()
        onCommit(OverlapTransitionConfig(startOffsetSeconds: timeline.startOffsetSeconds))
        dismiss()
    }
}
