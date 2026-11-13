import SwiftUI

/// Single stop / play / fade / loop cluster used by the shared transport.
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
    /// Draws the dark backing pill. Turn off when the cluster already sits on glass.
    var showsBackground: Bool = true
    var iconScale: CGFloat = 0.38

    var body: some View {
        HStack(spacing: 0) {
            AppIconButton(
                systemImage: "stop.fill",
                size: buttonSize,
                isEnabled: isLoaded,
                iconScale: iconScale,
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
                tint: AppColors.transportPlay,
                iconScale: iconScale,
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

            AppIconToggle(
                title: "Loop Section",
                systemImage: "repeat",
                isOn: isLooping,
                size: buttonSize,
                isEnabled: isLoaded && canLoop,
                tint: AppColors.transportLoop,
                iconScale: iconScale,
                action: onToggleLoop
            )
            .mappingControl(.loop, enabled: enablesInputMapping, cornerRadius: mappingCornerRadius)
        }
        .frame(height: buttonSize)
        .background {
            if showsBackground {
                RoundedRectangle(cornerRadius: buttonSize * 0.14, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay {
                        RoundedRectangle(cornerRadius: buttonSize * 0.14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.055), lineWidth: 0.5)
                    }
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
        AppIconToggle(
            title: "Fade Out",
            systemImage: "righttriangle.fill",
            isOn: isFadedOut || isFading,
            size: buttonSize,
            isEnabled: isLoaded,
            tint: AppColors.transportFade,
            iconScale: iconScale,
            // SF Symbol has the right angle on the bottom-left; mirror for idle (bottom-right).
            flipsImageHorizontally: !isFadedOut
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
            mappableLiveControl(action, cornerRadius: cornerRadius, isOutlined: false)
        } else {
            self
        }
    }
}

struct SharedTransportStrip: View {
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
    var enablesInputMapping: Bool = false

    var body: some View {
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
        .frame(maxWidth: .infinity)
    }
}

/// Transport stays in the bottom bar. `macOSPlacesControlsAtBottom` is the macOS editor toggle.
enum LiveTransportLayout {
    /// Set to false to put the macOS song-editor transport back in the toolbar.
    static let macOSPlacesControlsAtBottom = true
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

