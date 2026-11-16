import SwiftUI

/// A setlist header in the setlist strip: its title, and how long its segment runs when it has a time.
struct SetlistWaveformHeaderMarker: View {
    let title: String
    var timeSeconds: TimeInterval?
    /// Matches the MIDI-lane space reserved below song waveforms, so the
    /// header spans the same height as the surrounding song lanes.
    var extraHeight: CGFloat = 0

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    private static let minimumWidth: CGFloat = 96
    private static let maximumWidth: CGFloat = 180

    private var timeText: String? {
        guard let timeSeconds, timeSeconds > 0 else { return nil }
        return LiveSetlistDurationFormat.clock(for: timeSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
            Text(title)
                .font(AppTypography.Compact.sectionName)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
            if let timeText {
                Label(timeText, systemImage: "clock")
                    .font(AppTypography.Compact.sectionName)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, AppSpacing.xxxs)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        // Puts the first line of the title on the same line as the section and transition labels.
        .padding(.vertical, AppSpacing.xxs)
        .frame(minWidth: Self.minimumWidth, maxWidth: Self.maximumWidth, alignment: .topLeading)
        .frame(height: waveformHeight + extraHeight, alignment: .top)
        .padding(.trailing, AppSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
