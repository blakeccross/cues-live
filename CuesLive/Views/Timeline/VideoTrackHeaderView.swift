import SwiftUI

/// Track header for the video lane: name, where the movie starts, and its actions.
struct VideoTrackHeaderView: View {
    @Bindable var video: VideoTrack
    let laneHeight: CGFloat
    let isSelected: Bool
    let isFileMissing: Bool
    let canAlignToInsertion: Bool
    let onSelect: (PointerModifiers) -> Void
    let onRename: () -> Void
    let onShowWindow: () -> Void
    let onReplace: () -> Void
    let onAlignToInsertion: () -> Void
    let onResetStart: () -> Void
    let onDelete: () -> Void
    /// Drag distance downward from the press, in points.
    let onResize: (CGFloat) -> Void
    let onResizeEnded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .top, spacing: AppSpacing.compact) {
                Image(systemName: "film")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                TextField("Video", text: $video.displayName)
                    .textFieldStyle(.plain)
                    .font(AppTypography.captionEmphasized)
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    .onSubmit { onRename() }
            }

            HStack(spacing: AppSpacing.compact) {
                Text(detailLabel)
                    .font(AppTypography.Compact.detail)
                    .foregroundStyle(isFileMissing ? AppColors.warning : AppColors.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onShowWindow) {
                    Text("Show")
                        .font(AppTypography.Compact.label)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, AppSpacing.chipInsets.top)
                        .background(AppColors.Timeline.mixButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
                }
                .buttonStyle(.plain)
                .help("Open the Video window")
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.compact)
        .frame(width: TimelineLayout.trackHeaderWidth, height: laneHeight, alignment: .topLeading)
        .clipped()
        .background {
            if isSelected {
                Rectangle()
                    .fill(AppColors.trackHeaderSelected)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { menuItems }
        .onTapGesture { onSelect(.current) }
        .overlay(alignment: .bottom) {
            TrackLaneResizeHandle(onChanged: onResize, onEnded: onResizeEnded)
                .frame(maxWidth: .infinity)
                .frame(height: 6)
                .offset(y: 2)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Show Video Window", action: onShowWindow)
        Button("Replace Video…", action: onReplace)
        Divider()
        Button("Start Video at Insertion", action: onAlignToInsertion)
            .disabled(!canAlignToInsertion)
        Button("Start Video at Song Start", action: onResetStart)
            .disabled(video.startSeconds == 0)
        Divider()
        Button("Remove Video", role: .destructive, action: onDelete)
    }

    private var detailLabel: String {
        if isFileMissing {
            return "File missing"
        }
        return "Starts at \(Self.formattedStart(video.startSeconds))"
    }

    /// `m:ss.mmm`, with a leading minus for a movie that starts before the song.
    static func formattedStart(_ seconds: TimeInterval) -> String {
        let sign = seconds < 0 ? "-" : ""
        let totalMilliseconds = Int((abs(seconds) * 1000).rounded())
        let minutes = totalMilliseconds / 60_000
        let remainder = Double(totalMilliseconds % 60_000) / 1000
        return sign + String(format: "%d:%06.3f", minutes, remainder)
    }
}
