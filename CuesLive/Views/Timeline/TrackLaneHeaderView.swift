import SwiftUI

struct TrackLaneHeaderView: View {
    @Bindable var track: AudioTrack
    @Bindable private var audioEngine = AudioEngineManager.shared
    let laneHeight: CGFloat
    let isSelected: Bool
    let groups: [TrackGroup]
    let onSelect: (PointerModifiers) -> Void
    let onMixChange: () -> Void
    let onGroupChange: () -> Void
    let onManageGroups: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    /// Drag distance downward from the press, in points.
    let onResize: (CGFloat) -> Void
    let onResizeEnded: () -> Void

    private var trackColors: (header: Color, body: Color) {
        TrackGroupPalette.colors(for: track.group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(track.displayName)
                .font(AppTypography.captionEmphasized)
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, AppSpacing.xxs)

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(spacing: AppSpacing.compact) {
                    TrackMixButton(
                        label: "M",
                        isActive: track.isMuted,
                        activeColor: AppColors.muteActive
                    ) {
                        track.isMuted.toggle()
                        onMixChange()
                    }

                    TrackMixButton(
                        label: "S",
                        isActive: track.isSolo,
                        activeColor: AppColors.soloActive
                    ) {
                        track.isSolo.toggle()
                        onMixChange()
                    }

                    TrackVolumeField(
                        volume: $track.volume,
                        onLiveChange: applyLiveMix,
                        onEditingEnded: onMixChange
                    )

                    TrackPanField(
                        pan: $track.pan,
                        onLiveChange: applyLiveMix,
                        onEditingEnded: onMixChange
                    )
                }

                groupPicker
            }
            .padding(.horizontal, AppSpacing.xs)
            .padding(.bottom, AppSpacing.compact)
        }
        .frame(width: TimelineLayout.trackHeaderWidth, height: laneHeight, alignment: .topLeading)
        .clipped()
        .background {
            if isSelected {
                Rectangle()
                    .fill(AppColors.trackHeaderSelected)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") {
                onRename()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .onTapGesture { onSelect(.current) }
        .overlay(alignment: .bottom) {
            TrackLaneResizeHandle(onChanged: onResize, onEnded: onResizeEnded)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .offset(y: 2)
        }
    }

    private func applyLiveMix() {
        audioEngine.applyLiveTrackMix(id: track.id, volume: Float(track.volume), pan: Float(track.pan))
    }

    private var groupPicker: some View {
        Menu {
            Button("No Group") {
                track.group = nil
                onGroupChange()
            }

            ForEach(groups) { group in
                Button(group.name) {
                    track.group = group
                    onGroupChange()
                }
            }

            Divider()

            Button("Manage Groups…") {
                onManageGroups()
            }
        } label: {
            HStack(spacing: AppSpacing.xxs) {
                Text(track.group?.name ?? "No Group")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppTypography.Compact.glyph)
            }
            .font(AppTypography.caption2)
            .foregroundStyle(trackColors.body)
            .padding(AppSpacing.chipInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.Timeline.mixButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FlexibleControlSizing())
    }
}

private struct FlexibleControlSizing: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonSizing(.flexible)
        } else {
            content
        }
    }
}
