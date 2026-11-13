import SwiftUI

/// Floating glass now-playing bar for the live setlist: transport on the left, the current
/// song and what is up next in the middle, and the mixer and song editor toggles on the right.
struct LiveSetlistNowPlayingInfoView: View {
    let coordinator: PlaybackCoordinator
    @Bindable var sectionLoop: SectionLoopController
    @Bindable var groupMixFade: GroupMixFadeController
    let isLoaded: Bool
    let canLoop: Bool
    let isMixerVisible: Bool
    let isEditorOpen: Bool
    let onStop: () -> Void
    let onPlay: () -> Void
    let onPause: () -> Void
    let onToggleLoop: () -> Void
    let onToggleFade: () -> Void
    let onToggleMixer: () -> Void
    let onToggleEditor: () -> Void

    // Hit targets at or above Apple's defaults (HIG, Buttons: 28 pt on macOS, 44 pt on iPad),
    // with 20 pt glyphs on macOS and 24 pt on iPad.
    #if os(macOS)
    private static let controlSize: CGFloat = 32
    private static let iconScale: CGFloat = 20 / 32
    #else
    private static let controlSize: CGFloat = 44
    private static let iconScale: CGFloat = 24 / 44
    #endif

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            transport
                .frame(maxWidth: .infinity, alignment: .leading)

            songTitle

            toggles
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.md)
        .appGlassBackground(in: Capsule())
        .frame(maxWidth: 680)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xs)
        .padding(.bottom, AppSpacing.sm)
    }

    private var transport: some View {
        SharedTransportControlButtons(
            buttonSize: Self.controlSize,
            isPlaying: coordinator.isPlaying,
            isLoaded: isLoaded,
            isLooping: sectionLoop.isLooping,
            canLoop: canLoop,
            isFadedOut: groupMixFade.isFadedOut,
            isFading: groupMixFade.isFading,
            onStop: onStop,
            onPlay: onPlay,
            onPause: onPause,
            onToggleLoop: onToggleLoop,
            onToggleFade: onToggleFade,
            enablesInputMapping: true,
            showsBackground: false,
            iconScale: Self.iconScale
        )
    }

    private var songTitle: some View {
        VStack(spacing: 1) {
            Text(coordinator.currentSong?.name ?? "Not Playing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(coordinator.currentSong == nil ? AppColors.textSecondary : AppColors.textPrimary)
            if let upNext = coordinator.nextSong?.name, !upNext.isEmpty {
                Text("Up Next: \(upNext)")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .multilineTextAlignment(.center)
        .frame(minWidth: 120, maxWidth: 300)
        .accessibilityElement(children: .combine)
    }

    private var toggles: some View {
        HStack(spacing: 0) {
            AppIconToggle(
                title: "Group Mixer",
                systemImage: "slider.vertical.3",
                isOn: isMixerVisible,
                size: Self.controlSize,
                tint: AppColors.accent,
                iconScale: Self.iconScale,
                action: onToggleMixer
            )
            .help("Group Mixer")

            AppIconToggle(
                title: "Song Editor",
                systemImage: "rectangle.badge.plus",
                isOn: isEditorOpen,
                size: Self.controlSize,
                isEnabled: coordinator.currentSong != nil,
                tint: AppColors.accent,
                iconScale: Self.iconScale,
                action: onToggleEditor
            )
            .help("Edit the playing song")
        }
    }
}

/// Centered macOS toolbar title. Occupies `.principal` so trailing controls stay on the right.
struct LiveToolbarSongTitle: View {
    let title: String
    var upNext: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let upNext, !upNext.isEmpty {
                Text("Up Next: \"\(upNext)\"")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        // An empty title (no song loaded) would measure as zero-sized, which AppKit
        // logs as an ambiguous toolbar item.
        .frame(minWidth: 1, minHeight: 1)
    }
}
