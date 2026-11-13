#if os(macOS)
import SwiftUI

private enum SongTableLayout {
    static let tempoColumnID = "tempo"
    static let keyColumnID = "key"
    /// Below this table width the BPM and Key columns hide, leaving room for song names.
    static let compactWidth: CGFloat = 320
}

extension SongLibraryPanel {
    /// Apple Music–style song table: sortable columns and an inset rounded selection.
    /// Only the Song column has a flexible width, so it absorbs every pane resize and the
    /// actions column stays against the trailing edge.
    var songTable: some View {
        Table(
            of: Song.self,
            selection: $selection,
            sortOrder: $tableSortOrder,
            columnCustomization: $tableColumnCustomization
        ) {
            TableColumn("Song", value: \Song.name) { song in
                SongTitleCell(song: song)
            }
            .width(min: 120, ideal: 120)
            .disabledCustomizationBehavior(.all)

            TableColumn("BPM", value: \Song.tempoSortValue) { song in
                SongValueCell(text: song.bpm.map { "\(Int($0.rounded()))" } ?? "—")
            }
            .width(48)
            .customizationID(SongTableLayout.tempoColumnID)
            .disabledCustomizationBehavior(.reorder)

            TableColumn("Key", value: \Song.keySortValue) { song in
                SongValueCell(text: song.displayedKeyText ?? "—")
            }
            .width(44)
            .customizationID(SongTableLayout.keyColumnID)
            .disabledCustomizationBehavior(.reorder)

            TableColumn("") { song in
                songActionsMenu(for: song)
            }
            .width(24)
            .disabledCustomizationBehavior(.all)
        } rows: {
            ForEach(filteredSongs) { song in
                TableRow(song)
                    .draggable(SongDragPayload.string(for: song.id))
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width < SongTableLayout.compactWidth
        } action: { isCompact in
            let visibility: Visibility = isCompact ? .hidden : .visible
            tableColumnCustomization[visibility: SongTableLayout.tempoColumnID] = visibility
            tableColumnCustomization[visibility: SongTableLayout.keyColumnID] = visibility
        }
        .onDeleteCommand(perform: requestDeleteSelection)
        .onExitCommand { selection.removeAll() }
    }

    private func songActionsMenu(for song: Song) -> some View {
        Menu {
            songContextMenu(for: [song.id])
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions for \(song.name)")
    }
}

/// Song name over its time signature and track count, like a title over its album.
private struct SongTitleCell: View {
    let song: Song

    @Environment(\.backgroundProminence) private var backgroundProminence

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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: AppSpacing.xxs) {
                Text(song.name)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if song.smartGuideEnabled {
                    SmartGuideBadge()
                }
            }
            Text(details)
                .font(.callout)
                .foregroundStyle(
                    backgroundProminence == .increased
                        ? AppColors.textPrimary.opacity(0.8)
                        : AppColors.textTertiary
                )
                .lineLimit(1)
        }
        .padding(.vertical, AppSpacing.xxs)
    }
}

private struct SongValueCell: View {
    let text: String

    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(backgroundProminence == .increased ? AppColors.textPrimary : AppColors.textSecondary)
    }
}

/// Sort keys for the table. Songs missing a tempo or key sort first.
private extension Song {
    var tempoSortValue: Double {
        bpm ?? -1
    }

    var keySortValue: Int {
        baseKeyRaw
            .flatMap(SongMusicalKey.init(rawValue:))
            .map { $0.transposed(by: transposeSemitones).semitoneIndex } ?? -1
    }
}
#endif
