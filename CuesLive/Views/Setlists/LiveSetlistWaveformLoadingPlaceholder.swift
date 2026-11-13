import SwiftUI

/// Stand-in for the live waveform strip while a song loads, or when nothing is loaded.
struct LiveSetlistWaveformLoadingPlaceholder: View {
    var message: String?

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    private var panelHeight: CGFloat {
        LiveSetlistWaveformMetrics.laneHeight(for: waveformHeight)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .fill(AppColors.backgroundPrimary)
            .overlay {
                if let message {
                    ProgressView(message)
                        .tint(AppColors.accent)
                } else {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColors.separator, lineWidth: 0.5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: panelHeight)
            .redacted(reason: message == nil ? .placeholder : [])
    }
}
