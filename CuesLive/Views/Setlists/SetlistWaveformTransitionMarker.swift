import SwiftUI

/// How one song hands off to the next in the setlist strip: a block the height of a song lane
/// between the two songs, with its symbol and caption centered. A continue is green, a stop is red and
/// says so, and an overlap is green and opens its editor. It sits flush against the songs
/// beside it, shaded along those edges as if tucked under them.
struct SetlistWaveformTransitionMarker: View {
    let transition: SetlistTransition
    /// Read out to VoiceOver only; the block shows just the overlap symbol.
    var overlapSeconds: TimeInterval?
    /// False when a header comes next, so the trailing edge has no song to sit under.
    var isFollowedBySong = true
    /// Matches the MIDI-lane space reserved below song waveforms.
    var extraHeight: CGFloat = 0
    var onTap: (() -> Void)?

    @Environment(\.liveSetlistWaveformHeight) private var waveformHeight

    /// How far the songs' shadow reaches into the block.
    private static let shadowWidth: CGFloat = 9
    /// Shadow strength across its width: a fast drop then a long faint tail, the way a blurred
    /// shadow fades, rather than a straight ramp.
    private static let shadowFalloff: [(location: CGFloat, strength: Double)] = [
        (0, 1), (0.15, 0.62), (0.35, 0.3), (0.55, 0.13), (0.8, 0.04), (1, 0),
    ]

    var body: some View {
        VStack(spacing: 0) {
            block
            Color.clear.frame(height: extraHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var block: some View {
        if let onTap {
            Button(action: onTap) {
                content
            }
            .buttonStyle(.plain)
            .appLinkPointer()
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: systemImage)
                .font(AppTypography.Compact.transitionGlyph)
            if let caption {
                Text(caption)
                    .font(AppTypography.Compact.sectionName)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .foregroundStyle(AppColors.LiveWaveform.sectionLabel)
        .padding(.horizontal, AppSpacing.xs)
        .frame(height: waveformHeight)
        .background {
            ZStack {
                fill
                edgeShadows
            }
        }
        .fixedSize()
    }

    private var edgeShadows: some View {
        HStack(spacing: 0) {
            edgeShadow(fadingTo: .trailing)
            Spacer(minLength: 0)
            if isFollowedBySong {
                edgeShadow(fadingTo: .leading)
            }
        }
    }

    private func edgeShadow(fadingTo end: UnitPoint) -> some View {
        LinearGradient(
            stops: Self.shadowFalloff.map { location, strength in
                Gradient.Stop(color: AppColors.Live.transitionEdgeShadow.opacity(strength), location: location)
            },
            startPoint: end == .trailing ? .leading : .trailing,
            endPoint: end
        )
        .frame(width: Self.shadowWidth)
    }

    private var systemImage: String {
        switch transition {
        case .continue: "chevron.forward"
        case .stop: "stop.fill"
        case .overlap: transition.systemImage
        }
    }

    private var fill: Color {
        switch transition {
        case .continue, .overlap: AppColors.Live.transitionContinueRibbon
        case .stop: AppColors.Live.transitionStopRibbon
        }
    }

    /// Text beside the symbol: the word for a stop.
    private var caption: String? {
        transition == .stop ? transition.label : nil
    }

    private var accessibilityText: String {
        guard transition == .overlap, let overlapSeconds, overlapSeconds > 0 else { return transition.label }
        let length = Duration.seconds(overlapSeconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
        return "\(transition.label), \(length)"
    }
}
