#if os(macOS)
import SwiftUI

/// One song in the macOS library list: a single line with the name, then tempo, key, and
/// meter in narrow trailing columns so the values line up down the list.
struct SongLibraryListRow: View {
    static let tempoColumnWidth: CGFloat = 28
    static let keyColumnWidth: CGFloat = 34
    static let meterColumnWidth: CGFloat = 30

    let song: Song

    @Environment(\.backgroundProminence) private var backgroundProminence

    /// Selected rows sit on the accent highlight, where secondary text would wash out.
    private var secondaryColor: Color {
        backgroundProminence == .increased ? AppColors.textPrimary.opacity(0.8) : AppColors.textSecondary
    }

    private var tempoText: String? {
        song.bpm.map { "\(Int($0.rounded()))" }
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xxs) {
                Text(song.name)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if song.smartGuideEnabled {
                    SmartGuideBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            detailColumn(tempoText, width: Self.tempoColumnWidth)
                .help("Tempo (BPM)")
            detailColumn(song.displayedKeyText, width: Self.keyColumnWidth)
                .help("Key")
            detailColumn(song.timeSignatureDisplay, width: Self.meterColumnWidth)
                .help("Time signature")
        }
        .font(.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func detailColumn(_ value: String?, width: CGFloat) -> some View {
        Text(value ?? "–")
            .font(.callout.monospacedDigit())
            .foregroundStyle(secondaryColor)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private var accessibilityDescription: String {
        var parts = [song.name]
        if let tempoText {
            parts.append("\(tempoText) BPM")
        }
        if let key = song.displayedKeyText {
            parts.append("key \(key)")
        }
        if let meter = song.timeSignatureDisplay {
            parts.append(meter)
        }
        if song.smartGuideEnabled {
            parts.append("Smart Guide on")
        }
        return parts.joined(separator: ", ")
    }
}
#endif
