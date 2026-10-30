import SwiftUI

struct TransportStatusSnapshot {
    let position: String
    let bpm: String
    let meter: String
    let key: String
}

enum SharedTransportStripChrome: Equatable {
    /// Metadata + transport buttons + position readout (landscape / macOS toolbar).
    case full
    /// Portrait bottom bar: song info above shared transport buttons.
    case portraitBottom

    var showsControls: Bool { true }

    var stacksInfoAboveControls: Bool {
        self == .portraitBottom
    }
}

/// Single stop / play / fade / loop cluster used by toolbar and portrait bottom bar.
struct SharedTransportControlButtons: View {
    let buttonSize: CGFloat
    let isPlaying: Bool
    let isLoaded: Bool
    let isLooping: Bool
    let canLoop: Bool
    let isFadedOut: Bool
    let isFading: Bool
    let onStop: () -> Void
    let onPlay: () -> Void
    let onPause: () -> Void
    let onToggleLoop: () -> Void
    var onToggleFade: (() -> Void)? = nil
    var enablesInputMapping: Bool = false

    private var transportActiveGreen: Color { Color(red: 0.49, green: 0.75, blue: 0.48) }
    private var transportFadeRed: Color { Color(red: 0.86, green: 0.28, blue: 0.28) }
    private var transportLoopPurple: Color { Color(red: 0.72, green: 0.48, blue: 1.00) }

    var body: some View {
        HStack(spacing: 0) {
            AppIconButton(
                systemImage: "stop.fill",
                size: buttonSize,
                isEnabled: isLoaded,
                accessibilityLabel: "Stop"
            ) {
                onStop()
            }
            .mappingControl(.stop, enabled: enablesInputMapping, cornerRadius: mappingCornerRadius)

            AppIconButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                size: buttonSize,
                isActive: isPlaying,
                isEnabled: isLoaded,
                cornerRadius: buttonSize * 0.14,
                activeBackgroundColor: transportActiveGreen,
                accessibilityLabel: isPlaying ? "Pause" : "Play"
            ) {
                if isPlaying {
                    onPause()
                } else {
                    onPlay()
                }
            }
            .mappingControl(.playPause, enabled: enablesInputMapping, cornerRadius: mappingCornerRadius)

            fadeButton

            AppIconButton(
                systemImage: "repeat",
                size: buttonSize,
                isActive: isLooping,
                isEnabled: isLoaded && canLoop,
                cornerRadius: buttonSize * 0.14,
                activeBackgroundColor: transportLoopPurple,
                accessibilityLabel: isLooping ? "End Loop" : "Loop Section"
            ) {
                onToggleLoop()
            }
            .mappingControl(.loop, enabled: enablesInputMapping, cornerRadius: mappingCornerRadius)
        }
        .frame(height: buttonSize)
        .background {
            RoundedRectangle(cornerRadius: buttonSize * 0.14, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay {
                    RoundedRectangle(cornerRadius: buttonSize * 0.14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.055), lineWidth: 0.5)
                }
        }
    }

    private var mappingCornerRadius: CGFloat { buttonSize * 0.14 }

    @ViewBuilder
    private var fadeButton: some View {
        Group {
            if isFading {
                TimelineView(.animation(minimumInterval: 0.35)) { context in
                    let blinkDim = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 2 == 0
                    fadeButtonContent(opacity: blinkDim ? 0.28 : 1)
                }
            } else {
                fadeButtonContent(opacity: 1)
            }
        }
        .mappingControl(.fade, enabled: enablesInputMapping, cornerRadius: mappingCornerRadius)
    }

    private func fadeButtonContent(opacity: Double) -> some View {
        AppIconButton(
            systemImage: "righttriangle.fill",
            size: buttonSize,
            isActive: isFadedOut || isFading,
            isEnabled: isLoaded,
            cornerRadius: buttonSize * 0.14,
            activeBackgroundColor: transportFadeRed,
            // SF Symbol has the right angle on the bottom-left; mirror for idle (bottom-right).
            flipsImageHorizontally: !isFadedOut,
            accessibilityLabel: isFadedOut ? "Fade In" : "Fade Out"
        ) {
            onToggleFade?()
        }
        .opacity(opacity)
        .animation(AppAnimation.fadeQuick, value: isFadedOut)
    }
}

private extension View {
    @ViewBuilder
    func mappingControl(
        _ action: MappableLiveAction,
        enabled: Bool,
        cornerRadius: CGFloat
    ) -> some View {
        if enabled {
            mappableLiveControl(action, cornerRadius: cornerRadius)
        } else {
            self
        }
    }
}

struct SharedTransportStrip<BPMPopover: View, MeterPopover: View, KeyPopover: View>: View {
    let snapshot: TransportStatusSnapshot
    let buttonSize: CGFloat
    let isPlaying: Bool
    let isLoaded: Bool
    let isLooping: Bool
    let canLoop: Bool
    let onStop: () -> Void
    let onPlay: () -> Void
    let onPause: () -> Void
    let onToggleLoop: () -> Void
    var isFadedOut: Bool = false
    var isFading: Bool = false
    var onToggleFade: (() -> Void)? = nil
    var onReadoutHeightChange: ((CGFloat) -> Void)? = nil
    var chrome: SharedTransportStripChrome = .full
    var enablesInputMapping: Bool = false

    @Binding private var showingBPMPopover: Bool
    @Binding private var showingMeterPopover: Bool
    @Binding private var showingKeyPopover: Bool
    private let bpmPopover: () -> BPMPopover
    private let meterPopover: () -> MeterPopover
    private let keyPopover: () -> KeyPopover
    private let showsBPMPopover: Bool
    private let showsMeterPopover: Bool
    private let showsKeyPopover: Bool

    init(
        snapshot: TransportStatusSnapshot,
        buttonSize: CGFloat,
        isPlaying: Bool,
        isLoaded: Bool,
        isLooping: Bool,
        canLoop: Bool,
        onStop: @escaping () -> Void,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggleLoop: @escaping () -> Void,
        isFadedOut: Bool = false,
        isFading: Bool = false,
        onToggleFade: (() -> Void)? = nil,
        onReadoutHeightChange: ((CGFloat) -> Void)? = nil,
        chrome: SharedTransportStripChrome = .full,
        enablesInputMapping: Bool = false,
        showingBPMPopover: Binding<Bool> = .constant(false),
        showingMeterPopover: Binding<Bool> = .constant(false),
        showingKeyPopover: Binding<Bool> = .constant(false),
        @ViewBuilder bpmPopover: @escaping () -> BPMPopover,
        @ViewBuilder meterPopover: @escaping () -> MeterPopover,
        @ViewBuilder keyPopover: @escaping () -> KeyPopover
    ) {
        self.snapshot = snapshot
        self.buttonSize = buttonSize
        self.isPlaying = isPlaying
        self.isLoaded = isLoaded
        self.isLooping = isLooping
        self.canLoop = canLoop
        self.onStop = onStop
        self.onPlay = onPlay
        self.onPause = onPause
        self.onToggleLoop = onToggleLoop
        self.isFadedOut = isFadedOut
        self.isFading = isFading
        self.onToggleFade = onToggleFade
        self.onReadoutHeightChange = onReadoutHeightChange
        self.chrome = chrome
        self.enablesInputMapping = enablesInputMapping
        _showingBPMPopover = showingBPMPopover
        _showingMeterPopover = showingMeterPopover
        _showingKeyPopover = showingKeyPopover
        self.bpmPopover = bpmPopover
        self.meterPopover = meterPopover
        self.keyPopover = keyPopover
        self.showsBPMPopover = BPMPopover.self != EmptyView.self
        self.showsMeterPopover = MeterPopover.self != EmptyView.self
        self.showsKeyPopover = KeyPopover.self != EmptyView.self
    }

    var body: some View {
        if chrome.stacksInfoAboveControls {
            VStack(spacing: AppSpacing.sm) {
                songInfoRow
                HStack {
                    Spacer(minLength: 0)
                    controlButtons
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                transportMetadata
                controlButtons
                positionReadout
            }
        }
    }

    private var songInfoRow: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Spacer(minLength: 0)
            transportMetadata
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var positionReadout: some View {
        TransportStatusReadout(position: snapshot.position)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SharedTransportReadoutHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
            .onPreferenceChange(SharedTransportReadoutHeightPreferenceKey.self) { height in
                guard height > 0 else { return }
                onReadoutHeightChange?(height)
            }
    }

    private var controlButtons: some View {
        SharedTransportControlButtons(
            buttonSize: buttonSize,
            isPlaying: isPlaying,
            isLoaded: isLoaded,
            isLooping: isLooping,
            canLoop: canLoop,
            isFadedOut: isFadedOut,
            isFading: isFading,
            onStop: onStop,
            onPlay: onPlay,
            onPause: onPause,
            onToggleLoop: onToggleLoop,
            onToggleFade: onToggleFade,
            enablesInputMapping: enablesInputMapping
        )
    }

    private var transportMetadata: some View {
        HStack(spacing: AppSpacing.sm) {
            Group {
                if showsBPMPopover {
                    Button {
                        showingBPMPopover = true
                    } label: {
                        metadataText(snapshot.bpm)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingBPMPopover, arrowEdge: .bottom) {
                        bpmPopover()
                    }
                } else {
                    metadataText(snapshot.bpm)
                }
            }
            .accessibilityLabel("Tempo \(snapshot.bpm)")

            metadataDivider

            Group {
                if showsMeterPopover {
                    Button {
                        showingMeterPopover = true
                    } label: {
                        metadataText(snapshot.meter)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingMeterPopover, arrowEdge: .bottom) {
                        meterPopover()
                    }
                } else {
                    metadataText(snapshot.meter)
                }
            }
            .accessibilityLabel("Time signature \(snapshot.meter)")

            metadataDivider

            Group {
                if showsKeyPopover {
                    Button {
                        showingKeyPopover = true
                    } label: {
                        metadataText(snapshot.key)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingKeyPopover, arrowEdge: .bottom) {
                        keyPopover()
                    }
                } else {
                    metadataText(snapshot.key)
                }
            }
            .accessibilityLabel("Key \(snapshot.key)")
        }
        .fixedSize()
    }

    private func metadataText(_ value: String) -> some View {
        Text(value)
            .font(AppTypography.monoValue())
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(AppColors.separator)
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }
}

extension SharedTransportStrip where BPMPopover == EmptyView, MeterPopover == EmptyView, KeyPopover == EmptyView {
    init(
        snapshot: TransportStatusSnapshot,
        buttonSize: CGFloat,
        isPlaying: Bool,
        isLoaded: Bool,
        isLooping: Bool,
        canLoop: Bool,
        onStop: @escaping () -> Void,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggleLoop: @escaping () -> Void,
        isFadedOut: Bool = false,
        isFading: Bool = false,
        onToggleFade: (() -> Void)? = nil,
        onReadoutHeightChange: ((CGFloat) -> Void)? = nil,
        chrome: SharedTransportStripChrome = .full,
        enablesInputMapping: Bool = false
    ) {
        self.init(
            snapshot: snapshot,
            buttonSize: buttonSize,
            isPlaying: isPlaying,
            isLoaded: isLoaded,
            isLooping: isLooping,
            canLoop: canLoop,
            onStop: onStop,
            onPlay: onPlay,
            onPause: onPause,
            onToggleLoop: onToggleLoop,
            isFadedOut: isFadedOut,
            isFading: isFading,
            onToggleFade: onToggleFade,
            onReadoutHeightChange: onReadoutHeightChange,
            chrome: chrome,
            enablesInputMapping: enablesInputMapping,
            showingBPMPopover: .constant(false),
            showingMeterPopover: .constant(false),
            showingKeyPopover: .constant(false),
            bpmPopover: { EmptyView() },
            meterPopover: { EmptyView() },
            keyPopover: { EmptyView() }
        )
    }
}

/// iPhone portrait: compact width + regular height. Landscape phones use compact height.
enum LiveTransportLayout {
    /// macOS experiment: the transport lives in a bottom bar (like iPhone portrait) instead of
    /// the toolbar. Set to false to restore the toolbar transport.
    static let macOSPlacesControlsAtBottom = true

    static func placesControlsAtBottom(
        verticalSizeClass: UserInterfaceSizeClass?,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        #if os(iOS)
        verticalSizeClass == .regular && horizontalSizeClass == .compact
        #else
        macOSPlacesControlsAtBottom
        #endif
    }

    static func showsToolbarTransport(placesControlsAtBottom: Bool) -> Bool {
        !placesControlsAtBottom
    }

    static func bottomBarChrome(placesControlsAtBottom: Bool) -> SharedTransportStripChrome {
        placesControlsAtBottom ? .portraitBottom : .full
    }
}

/// Shared bottom-bar chrome for portrait transport controls.
struct LiveTransportBottomBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.backgroundSecondary)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppColors.separator)
                    .frame(height: 0.5)
            }
    }
}

private struct SharedTransportReadoutHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
