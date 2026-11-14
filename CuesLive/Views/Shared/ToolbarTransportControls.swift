import SwiftUI

/// Stop, play/pause, fade, and loop as native toolbar controls. Shared by the setlist window and
/// the song editor so both transports look and map the same; callers supply the state and actions.
struct ToolbarTransportControls: View {
    let isPlaying: Bool
    let isLoaded: Bool
    let isLooping: Bool
    let canLoop: Bool
    let isFadedOut: Bool
    let isFading: Bool
    let onStop: () -> Void
    let onPlayPause: () -> Void
    let onToggleFade: () -> Void
    let onToggleLoop: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
            }
            .help("Stop")
            .mappableLiveControl(.stop)

            playPauseButton

            fadeToggle

            Toggle(isOn: Binding(get: { isLooping }, set: { _ in onToggleLoop() })) {
                Label("Loop Section", systemImage: "repeat")
            }
            .tint(AppColors.transportLoop)
            .disabled(!canLoop)
            .help("Loop Section")
            .mappableLiveControl(.loop)
        }
        .labelStyle(.iconOnly)
        .toggleStyle(.button)
        .disabled(!isLoaded)
    }

    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
        }
        .foregroundStyle(isPlaying ? AppColors.transportPlay : AppColors.textPrimary)
        .help(isPlaying ? "Pause" : "Play")
        .mappableLiveControl(.playPause)
    }

    /// Blinks while a fade is running so the state reads from across a stage.
    private var fadeToggle: some View {
        Group {
            if isFading {
                TimelineView(.animation(minimumInterval: 0.35)) { context in
                    let isDimmed = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 2 == 0
                    fadeToggleContent.opacity(isDimmed ? 0.28 : 1)
                }
            } else {
                fadeToggleContent
            }
        }
        .mappableLiveControl(.fade)
    }

    private var fadeToggleContent: some View {
        Toggle(isOn: Binding(get: { isFadedOut || isFading }, set: { _ in onToggleFade() })) {
            Label {
                Text("Fade Out")
            } icon: {
                // The symbol's right angle is bottom-left; mirror it for idle (bottom-right).
                Image(systemName: "righttriangle.fill")
                    .scaleEffect(x: isFadedOut ? 1 : -1, y: 1)
            }
        }
        .tint(AppColors.transportFade)
        .help(isFadedOut ? "Fade In" : "Fade Out")
    }
}
