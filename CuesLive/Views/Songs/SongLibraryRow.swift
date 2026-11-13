import SwiftUI

#if os(iOS)
/// One song in the library: name and details, tempo and key columns, and a quick add-to-setlist button.
struct SongLibraryRow: View {
    static let tempoColumnWidth: CGFloat = 40
    static let keyColumnWidth: CGFloat = 32
    static let addButtonWidth: CGFloat = 28

    let song: Song
    let onAddToSetlist: () -> Void

    @Environment(\.backgroundProminence) private var backgroundProminence

    /// Selected rows sit on the accent highlight, where tertiary text would wash out.
    private var isHighlighted: Bool {
        backgroundProminence == .increased
    }

    private var secondaryColor: Color {
        isHighlighted ? AppColors.textPrimary.opacity(0.8) : AppColors.textTertiary
    }

    private var details: String {
        var parts: [String] = []
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

    private var tempoText: String {
        song.bpm.map { "\(Int($0.rounded()))" } ?? "—"
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xxs) {
                    Text(song.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    if song.smartGuideEnabled {
                        SmartGuideBadge()
                    }
                }
                Text(details)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(tempoText)
                .frame(width: Self.tempoColumnWidth, alignment: .trailing)
                .accessibilityLabel(song.bpm == nil ? "No tempo" : "\(tempoText) BPM")
            Text(song.displayedKeyText ?? "—")
                .frame(width: Self.keyColumnWidth, alignment: .center)
                .accessibilityLabel(song.displayedKeyText.map { "Key \($0)" } ?? "No key")

            addButton
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(isHighlighted ? AppColors.textPrimary : AppColors.textSecondary)
        .padding(.vertical, AppSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Add to Setlist", onAddToSetlist)
    }

    private var addButton: some View {
        Button(action: onAddToSetlist) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .frame(width: Self.addButtonWidth, height: Self.addButtonWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to setlist")
    }
}
#endif
