import SwiftUI

/// Transport, now-playing display, and view toggles for the live setlist window toolbar.
/// Laid out like Logic Pro's control bar: view toggles lead, transport and the song display
/// sit in the centre, and the setlist's own actions trail.
struct LiveSetlistTransportToolbarContent: ToolbarContent {
    let coordinator: PlaybackCoordinator
    let sectionLoop: SectionLoopController
    let groupMixFade: GroupMixFadeController
    let canLoop: Bool
    let isMixerVisible: Bool
    let isEditorOpen: Bool
    let onStop: () -> Void
    let onToggleLoop: () -> Void
    let onToggleFade: () -> Void
    let onToggleMixer: () -> Void
    let onToggleEditor: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: viewTogglePlacement) {
            Toggle(isOn: Binding(get: { isMixerVisible }, set: { _ in onToggleMixer() })) {
                Label("Group Mixer", systemImage: "slider.vertical.3")
            }
            .help("Group Mixer")

            LiveToolbarEditorToggle(
                coordinator: coordinator,
                isOn: isEditorOpen,
                action: onToggleEditor
            )
        }

        ToolbarItem(placement: .principal) {
            LiveToolbarTransportControls(
                coordinator: coordinator,
                sectionLoop: sectionLoop,
                groupMixFade: groupMixFade,
                canLoop: canLoop,
                onStop: onStop,
                onToggleLoop: onToggleLoop,
                onToggleFade: onToggleFade
            )
        }

        ToolbarItem(placement: .principal) {
            LiveToolbarNowPlaying(coordinator: coordinator)
        }
        .cuesHideSharedBackground()
    }

    private var viewTogglePlacement: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }
}

/// Stop, play/pause, fade, and loop as native toolbar controls. Reads the coordinator itself
/// so playback state changes redraw only the toolbar, not the setlist.
private struct LiveToolbarTransportControls: View {
    let coordinator: PlaybackCoordinator
    @Bindable var sectionLoop: SectionLoopController
    @Bindable var groupMixFade: GroupMixFadeController
    let canLoop: Bool
    let onStop: () -> Void
    let onToggleLoop: () -> Void
    let onToggleFade: () -> Void

    private var isLoaded: Bool {
        coordinator.isLoaded && !coordinator.isLoadingSong
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
            }
            .help("Stop")
            .mappableLiveControl(.stop, isOutlined: false)

            playPauseButton

            fadeToggle

            Toggle(isOn: Binding(get: { sectionLoop.isLooping }, set: { _ in onToggleLoop() })) {
                Label("Loop Section", systemImage: "repeat")
            }
            .tint(AppColors.transportLoop)
            .disabled(!canLoop)
            .help("Loop Section")
            .mappableLiveControl(.loop, isOutlined: false)
        }
        .labelStyle(.iconOnly)
        .toggleStyle(.button)
        .disabled(!isLoaded)
    }

    private var playPauseButton: some View {
        Button {
            if coordinator.isPlaying {
                coordinator.pause()
            } else {
                coordinator.play()
            }
        } label: {
            Label(
                coordinator.isPlaying ? "Pause" : "Play",
                systemImage: coordinator.isPlaying ? "pause.fill" : "play.fill"
            )
        }
        .foregroundStyle(coordinator.isPlaying ? AppColors.transportPlay : AppColors.textPrimary)
        .help(coordinator.isPlaying ? "Pause" : "Play")
        .mappableLiveControl(.playPause, isOutlined: false)
    }

    /// Blinks while a fade is running so the state reads from across a stage.
    @ViewBuilder
    private var fadeToggle: some View {
        Group {
            if groupMixFade.isFading {
                TimelineView(.animation(minimumInterval: 0.35)) { context in
                    let isDimmed = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 2 == 0
                    fadeToggleContent.opacity(isDimmed ? 0.28 : 1)
                }
            } else {
                fadeToggleContent
            }
        }
        .mappableLiveControl(.fade, isOutlined: false)
    }

    private var fadeToggleContent: some View {
        Toggle(
            isOn: Binding(
                get: { groupMixFade.isFadedOut || groupMixFade.isFading },
                set: { _ in onToggleFade() }
            )
        ) {
            Label {
                Text("Fade Out")
            } icon: {
                // The symbol's right angle is bottom-left; mirror it for idle (bottom-right).
                Image(systemName: "righttriangle.fill")
                    .scaleEffect(x: groupMixFade.isFadedOut ? 1 : -1, y: 1)
            }
        }
        .tint(AppColors.transportFade)
        .help(groupMixFade.isFadedOut ? "Fade In" : "Fade Out")
    }
}

/// The playing song and what is up next, centred beside the transport.
private struct LiveToolbarNowPlaying: View {
    let coordinator: PlaybackCoordinator

    var body: some View {
        LiveToolbarSongTitle(
            title: coordinator.currentSong?.name ?? "Not Playing",
            upNext: coordinator.nextSong?.name
        )
        .frame(minWidth: 120, maxWidth: 260)
        .accessibilityElement(children: .combine)
    }
}

/// Opens the song editor on the playing song. Disabled while nothing is loaded.
private struct LiveToolbarEditorToggle: View {
    let coordinator: PlaybackCoordinator
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Label("Song Editor", systemImage: "rectangle.badge.plus")
        }
        .disabled(coordinator.currentSong == nil)
        .help("Edit the playing song")
    }
}
