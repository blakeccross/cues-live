import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Row model

/// Display data for one setlist row. Local (SwiftData) and remote (DTO) setlists both map into this,
/// so they share a single list implementation.
struct SetlistRowModel: Identifiable {
    struct Song {
        var title: String
        var durationText: String
        var keyText: String? = nil
        var bpmText: String? = nil
        /// Position among songs only (headers are not counted).
        var playbackIndex: Int
        var hasMissingMedia: Bool = false
        var hasSmartGuide: Bool = false
        /// Transition to the next song; nil for the last song.
        var transition: SetlistTransition? = nil
    }

    enum Kind {
        case header(title: String, timeText: String?)
        case song(Song)
    }

    let id: AnyHashable
    let kind: Kind
}

/// What a row can do. Optional closures are hidden from the menu, swipe actions and
/// context menu when nil, so the remote list can offer a smaller set than the local one.
struct SetlistRowActions {
    var play: (() -> Void)?
    var edit: (() -> Void)?
    var relink: (() -> Void)?
    var transitions: [SetlistTransition] = []
    var setTransition: ((SetlistTransition) -> Void)?
    var remove: () -> Void
}

// MARK: - Song drag payload

/// Carries a library song across a drag from the sidebar into the setlist. A tagged string keeps
/// it a plain `Transferable` without needing a custom exported UTType.
enum SongDragPayload {
    private static let prefix = "cueslive-song:"

    static func string(for songID: UUID) -> String {
        prefix + songID.uuidString
    }

    static func songID(from string: String) -> UUID? {
        guard string.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(string.dropFirst(prefix.count)))
    }

    static func songIDs(from providers: [NSItemProvider]) async -> [UUID] {
        var ids: [UUID] = []
        for provider in providers where provider.canLoadObject(ofClass: String.self) {
            let string: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    continuation.resume(returning: value)
                }
            }
            if let string, let id = songID(from: string) {
                ids.append(id)
            }
        }
        return ids
    }
}

// MARK: - List

/// A plain native list: tap to play, drag to reorder (Edit mode on iOS), and one shared set of
/// row actions surfaced through the context menu, the trailing "…" button and iOS swipe actions.
struct SetlistListView: View {
    let rows: [SetlistRowModel]
    let currentIndex: Int
    let isPlaying: Bool
    @Binding var isEditing: Bool
    let actions: (SetlistRowModel) -> SetlistRowActions
    let onMove: (IndexSet, Int) -> Void
    var onAddHeader: (() -> Void)? = nil
    /// Called with the row index to insert at when a library song is dropped on the list.
    var onInsertSongs: ((Int, [UUID]) -> Void)? = nil

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        List {
            ForEach(rows) { row in
                rowView(row)
            }
            .onMove(perform: onMove)
            .onInsert(of: [.plainText]) { index, providers in
                guard let onInsertSongs else { return }
                Task { @MainActor in
                    let ids = await SongDragPayload.songIDs(from: providers)
                    if !ids.isEmpty { onInsertSongs(index, ids) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentShape(Rectangle())
        .contextMenu {
            if let onAddHeader {
                Button(action: onAddHeader) {
                    Label("Add Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, editModeBinding)
        // Avoid GeometryReader+List: after compact→regular rotation on device the list
        // can keep a blank content area. Recreate when size class changes.
        .id(verticalSizeClass)
        #endif
    }

    #if os(iOS)
    private var editModeBinding: Binding<EditMode> {
        Binding(
            get: { isEditing ? .active : .inactive },
            set: { isEditing = $0.isEditing }
        )
    }
    #endif

    @ViewBuilder
    private func rowView(_ row: SetlistRowModel) -> some View {
        let rowActions = actions(row)

        switch row.kind {
        case .header(let title, let timeText):
            SetlistHeaderRowView(
                title: title,
                timeText: timeText,
                showsMenu: !isEditing,
                menu: { SetlistRowMenuContent(model: row, actions: rowActions) }
            )
            .listRowSeparator(.hidden)
            .listRowBackground(AppColors.headerBand)
            .setlistSwipeActions(actions: rowActions)
            .contextMenu { SetlistRowMenuContent(model: row, actions: rowActions) }

        case .song(let song):
            let isCurrent = song.playbackIndex == currentIndex
            SetlistSongRowView(
                song: song,
                isCurrent: isCurrent,
                isFinished: song.playbackIndex < currentIndex,
                isPlaying: isPlaying,
                showsMenu: !isEditing,
                menu: { SetlistRowMenuContent(model: row, actions: rowActions) }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isEditing else { return }
                rowActions.play?()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Play") { rowActions.play?() }
            .appLinkPointer()
            .mappableLiveControl(.goToSong(song.playbackIndex), cornerRadius: AppRadius.sm)
            .listRowBackground(isCurrent ? AppColors.accent.opacity(0.18) : Color.clear)
            .setlistSwipeActions(actions: rowActions)
            .contextMenu { SetlistRowMenuContent(model: row, actions: rowActions) }
        }
    }
}

private extension View {
    /// Swipe to play (leading) or remove / edit (trailing). iOS only; macOS uses the menu.
    @ViewBuilder
    func setlistSwipeActions(actions: SetlistRowActions) -> some View {
        #if os(iOS)
        self
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let play = actions.play {
                    Button(action: play) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .tint(AppColors.accent)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: actions.remove) {
                    Label("Remove", systemImage: "trash")
                }
                if let edit = actions.edit {
                    Button(action: edit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        #else
        self
        #endif
    }
}

// MARK: - Row menu

/// The single source of truth for row actions: used by the context menu and the "…" button.
private struct SetlistRowMenuContent: View {
    let model: SetlistRowModel
    let actions: SetlistRowActions

    var body: some View {
        if let play = actions.play {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
            }
        }

        if case .song(let song) = model.kind,
           let current = song.transition,
           let setTransition = actions.setTransition,
           !actions.transitions.isEmpty {
            Menu {
                ForEach(actions.transitions) { option in
                    Button {
                        setTransition(option)
                    } label: {
                        Label(option.label, systemImage: option == current ? "checkmark" : option.systemImage)
                    }
                }
            } label: {
                Label("Transition to Next", systemImage: current.systemImage)
            }
        }

        if let edit = actions.edit {
            Button(action: edit) {
                Label("Edit", systemImage: "pencil")
            }
        }

        if let relink = actions.relink {
            Button(action: relink) {
                Label("Relink Missing Files…", systemImage: "exclamationmark.triangle")
            }
        }

        Button(role: .destructive, action: actions.remove) {
            Label("Remove from Setlist", systemImage: "trash")
        }
    }
}

private struct SetlistRowMenuButton<MenuContent: View>: View {
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        SwiftUI.Menu {
            menu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
        .setlistMenuFittedSizing()
        .appLinkPointer()
        .accessibilityLabel("More actions")
    }
}

// MARK: - Rows

private struct SetlistHeaderRowView<MenuContent: View>: View {
    let title: String
    let timeText: String?
    let showsMenu: Bool
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let timeText {
                Text(timeText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityLabel("Time \(timeText)")
            }

            if showsMenu {
                SetlistRowMenuButton(menu: menu)
            }
        }
        .frame(minHeight: 40)
    }
}

private struct SetlistSongRowView<MenuContent: View>: View {
    let song: SetlistRowModel.Song
    let isCurrent: Bool
    let isFinished: Bool
    let isPlaying: Bool
    let showsMenu: Bool
    @ViewBuilder let menu: () -> MenuContent

    private var detailText: String? {
        let parts = [song.keyText, song.bpmText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            leadingIndicator
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(isFinished ? AppColors.textTertiary : AppColors.textPrimary)
                    .lineLimit(2)

                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if song.hasMissingMedia {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityLabel("Missing audio files")
                    .help("Missing audio files — use Relink Missing Files in the menu")
            }

            if song.hasSmartGuide {
                SmartGuideBadge()
            }

            if let transition = song.transition {
                Image(systemName: transition.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(transition.badgeColor)
                    .accessibilityLabel("Transition to next: \(transition.label)")
                    .help("Transition to next: \(transition.label)")
            }

            Text(song.durationText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isCurrent ? AppColors.textSecondary : AppColors.textTertiary)
                .accessibilityLabel("Duration \(song.durationText)")

            if showsMenu {
                SetlistRowMenuButton(menu: menu)
            }
        }
        .frame(minHeight: AppSpacing.rowMinHeight)
        .opacity(isFinished ? 0.55 : 1)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if isCurrent {
            Image(systemName: "speaker.wave.2.fill")
                .font(.subheadline)
                .foregroundStyle(AppColors.accent)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .accessibilityLabel("Now playing")
        } else {
            Text("\(song.playbackIndex + 1)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityHidden(true)
        }
    }
}

/// Marks songs that have Smart Guide section call-outs turned on.
struct SmartGuideBadge: View {
    var body: some View {
        Image(systemName: "person.wave.2.fill")
            .font(.caption)
            .foregroundStyle(AppColors.accent)
            .accessibilityLabel("Smart Guide on")
            .help("Smart Guide on")
    }
}
