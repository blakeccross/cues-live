import SwiftUI

/// Shown while the audio output is gone and the engine is waiting to rebuild it.
struct AudioOutputLostBanner: View {
    private static let insets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    private static let contentSpacing: CGFloat = 10

    /// The device is listed but will not start, so waiting will not help.
    var isUnresponsive = false

    var body: some View {
        HStack(spacing: Self.contentSpacing) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(isUnresponsive ? "Audio device is not responding" : "Audio output disconnected")
                    .font(AppTypography.headline)
                Text(detail)
                    .font(AppTypography.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(Self.insets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.errorFill)
        .foregroundStyle(AppColors.textOnFill)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if isUnresponsive {
            return "The system can see the device but cannot start it. Power-cycle the interface, or restart Core Audio."
        }
        return "Playback is paused. It will reconnect when the device returns; press play to continue."
    }
}
