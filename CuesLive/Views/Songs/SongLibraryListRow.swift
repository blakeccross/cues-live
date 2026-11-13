#if os(macOS)
import SwiftUI

/// One song in the macOS library list: its name over tempo, key, meter, and track count.
struct SongLibraryListRow: View {
    let song: Song

    @Environment(\.backgroundProminence) private var backgroundProminence

    private var details: String {
        var parts: [String] = []
        if let bpm = song.bpm {
            parts.append("\(Int(bpm.rounded())) BPM")
        }
        if let key = song.displayedKeyText {
            parts.append(key)
        }
        if let timeSignature = song.timeSignatureDisplay {
            parts.append(timeSignature)
        }
        switch song.tracks.count {
        case 0: parts.append("No tracks")
        case 1: parts.append("1 track")
        case let count: parts.append("\(count) tracks")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppSpacing.xxs) {
                Text(song.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if song.smartGuideEnabled {
                    SmartGuideBadge()
                }
            }
            Text(details)
                .font(.callout.monospacedDigit())
                .foregroundStyle(
                    backgroundProminence == .increased
                        ? AppColors.textPrimary.opacity(0.8)
                        : AppColors.textSecondary
                )
                .lineLimit(1)
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}
#endif
