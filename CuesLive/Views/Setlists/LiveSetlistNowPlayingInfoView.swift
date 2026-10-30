import SwiftUI

struct LiveSetlistNowPlayingInfoView: View {
    let coordinator: PlaybackCoordinator
    @Bindable var sectionLoop: SectionLoopController
    @Bindable var groupMixFade: GroupMixFadeController
    let isLoaded: Bool
    let canLoop: Bool
    @Binding var infoPanelHeight: CGFloat
    let onStop: () -> Void
    let onPlay: () -> Void
    let onPause: () -> Void
    let onToggleLoop: () -> Void
    let onToggleFade: () -> Void
    var chrome: SharedTransportStripChrome = .full

    var body: some View {
        Group {
            if coordinator.isPlaying {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { _ in
                    transportContent(at: coordinator.livePlayheadTime())
                }
            } else {
                transportContent(at: coordinator.currentTime)
            }
        }
    }

    private func transportContent(at time: TimeInterval) -> some View {
        SharedTransportStrip(
            snapshot: displaySnapshot(at: time),
            buttonSize: max(infoPanelHeight, 44),
            isPlaying: coordinator.isPlaying,
            isLoaded: isLoaded,
            isLooping: sectionLoop.isLooping,
            canLoop: canLoop,
            onStop: onStop,
            onPlay: onPlay,
            onPause: onPause,
            onToggleLoop: onToggleLoop,
            isFadedOut: groupMixFade.isFadedOut,
            isFading: groupMixFade.isFading,
            onToggleFade: onToggleFade,
            onReadoutHeightChange: { height in
                infoPanelHeight = height
            },
            chrome: chrome,
            enablesInputMapping: true
        )
    }

    private func displaySnapshot(at time: TimeInterval) -> TransportStatusSnapshot {
        guard let song = coordinator.currentSong else {
            return TransportStatusSnapshot(
                position: "- - -",
                bpm: "-",
                meter: "-",
                key: "-"
            )
        }

        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        let tempoChanges = projectState.tempoChanges
        let timeSignatureChanges = projectState.timeSignatureChanges
        let position = MeasureTiming.position(
            at: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let measure = position.bar
        let signature = MeasureTiming.numeratorDenominatorForMeasure(
            measure,
            changes: timeSignatureChanges
        )
        let bpm = MeasureTiming.activeBPM(
            at: time,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )

        return TransportStatusSnapshot(
            position: MeasureTiming.formatTransportPosition(position),
            bpm: String(format: "%.1f", bpm),
            meter: "\(signature.numerator)/\(signature.denominator)",
            key: song.transportKeyText
        )
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
    }
}
