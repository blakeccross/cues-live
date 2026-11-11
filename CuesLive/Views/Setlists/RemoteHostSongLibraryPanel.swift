import SwiftUI

private enum RemoteHostSongLibrarySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case name = "Name"

    var id: String { rawValue }
}

/// Browse-only host song library for remote clients (add to setlist; no local media edits).
struct RemoteHostSongLibraryPanel: View {
    let songs: [RemoteLibrarySongDTO]
    var onDismiss: () -> Void
    var onAddToSetlist: (RemoteLibrarySongDTO) -> Void

    @State private var searchText = ""
    @State private var sortOrder: RemoteHostSongLibrarySortOrder = .newest

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredSongs: [RemoteLibrarySongDTO] {
        var result = songs

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        switch sortOrder {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            songList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .background(AppColors.backgroundSecondary)
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button(role: .close) {
                        onDismiss()
                    }
                } else {
                    Button("Close") {
                        onDismiss()
                    }
                }
            }
        }
        #endif
    }

    private var searchBar: some View {
        HStack(spacing: AppSpacing.xs) {
            AppSearchField(text: $searchText)

            if hasActiveSearch {
                Button("Clear") {
                    searchText = ""
                }
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .buttonStyle(.plain)
            }

            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(RemoteHostSongLibrarySortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(AppColors.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Sort songs")
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.xs)
        .padding(.bottom, AppSpacing.xs)
    }

    @ViewBuilder
    private var songList: some View {
        if songs.isEmpty {
            AppEmptyState(
                title: "No Songs on Host",
                systemImage: "music.note",
                description: "The host song library is empty."
            )
            .padding(.top, AppSpacing.sm)
            Spacer(minLength: 0)
        } else if filteredSongs.isEmpty {
            AppEmptyState(
                title: "No Results",
                systemImage: "magnifyingglass",
                description: "No songs match \"\(searchText)\"."
            )
            .padding(.top, AppSpacing.sm)
            Spacer(minLength: 0)
        } else {
            List {
                ForEach(filteredSongs) { song in
                    RemoteHostSongLibraryRow(
                        song: song,
                        onAddToSetlist: { onAddToSetlist(song) }
                    )
                    .contextMenu {
                        Button {
                            onAddToSetlist(song)
                        } label: {
                            Label("Add to Setlist", systemImage: "plus")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(AppColors.separator)
        }
    }
}

private struct RemoteHostSongLibraryRow: View {
    let song: RemoteLibrarySongDTO
    let onAddToSetlist: () -> Void

    private var subtitle: String {
        let trackText = song.trackCount == 0 ? "No tracks" : "\(song.trackCount) tracks"
        if let bpm = song.bpm {
            return "\(Int(bpm.rounded())) bpm — \(trackText)"
        }
        return trackText
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if song.smartGuideEnabled {
                SmartGuideBadge()
            }

            Button(action: onAddToSetlist) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appLinkPointer()
            .accessibilityLabel("Add to setlist")
        }
    }
}
