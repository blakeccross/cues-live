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
        /// Arrangement sections, listed when the row is expanded.
        var sections: [SongSection] = []
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

/// Playhead and cue state for the expanded section lists, plus how to act on a tapped section.
struct SetlistSectionPlayback {
    var playheadTime: () -> TimeInterval
    var isPlaying: Bool
    /// The clock time while stopped, so seeks redraw the progress without a running timeline.
    var idlePlayheadTime: TimeInterval?
    var cuedSectionID: UUID?
    var cueFlashPhase: Bool
    /// Cues the section in the current song, or jumps to it in another song.
    var selectSection: (_ playbackIndex: Int, _ section: SongSection) -> Void
}

// MARK: - Song drag payload

/// Carries a library song across a drag from the song library into the setlist. A tagged string keeps
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
    /// Enables expandable section lists under song rows.
    var sectionPlayback: SetlistSectionPlayback? = nil
    /// Inset of row content from the list's edges. Rows are padded rather than the list,
    /// so the scroller stays at the edge.
    var rowHorizontalPadding: CGFloat = 0

    /// Rows the user expanded or collapsed by hand; others follow the current song.
    @State private var expansionOverrides: [AnyHashable: Bool] = [:]

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
        .animation(AppAnimation.springSmooth, value: currentIndex)
        .onChange(of: currentIndex) { _, _ in
            expansionOverrides.removeAll()
        }
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
            .padding(.horizontal, rowHorizontalPadding)
            .listRowSeparator(.hidden)
            .listRowBackground(AppColors.headerBand)
            .setlistSwipeActions(actions: rowActions)
            .contextMenu { SetlistRowMenuContent(model: row, actions: rowActions) }

        case .song(let song):
            songRow(row, song: song, actions: rowActions)
        }
    }

    private func songRow(
        _ row: SetlistRowModel,
        song: SetlistRowModel.Song,
        actions rowActions: SetlistRowActions
    ) -> some View {
        let isCurrent = song.playbackIndex == currentIndex
        let expansion = expansionBinding(for: row, song: song)
        return VStack(spacing: 0) {
            SetlistSongRowView(
                song: song,
                isCurrent: isCurrent,
                isFinished: song.playbackIndex < currentIndex,
                isPlaying: isPlaying,
                showsMenu: !isEditing,
                menu: { SetlistRowMenuContent(model: row, actions: rowActions, sectionsExpanded: expansion) }
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

            if let sectionPlayback, expansion?.wrappedValue == true {
                SetlistSectionListView(
                    sections: song.sections,
                    playbackIndex: song.playbackIndex,
                    isCurrent: isCurrent,
                    isEnabled: !isEditing,
                    playback: sectionPlayback
                )
                .padding(.bottom, AppSpacing.xs)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, rowHorizontalPadding)
        .listRowBackground(Color.clear)
        .setlistSwipeActions(actions: rowActions)
        .contextMenu { SetlistRowMenuContent(model: row, actions: rowActions, sectionsExpanded: expansion) }
    }

    /// Nil when the row can't expand. Otherwise a manual override wins, and the current song
    /// opens by default.
    private func expansionBinding(for row: SetlistRowModel, song: SetlistRowModel.Song) -> Binding<Bool>? {
        guard sectionPlayback != nil, !isEditing, !song.sections.isEmpty else { return nil }
        let isCurrent = song.playbackIndex == currentIndex
        return Binding(
            get: { expansionOverrides[row.id] ?? isCurrent },
            set: { expansionOverrides[row.id] = $0 }
        )
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
    /// Nil when the song has no sections to show.
    var sectionsExpanded: Binding<Bool>? = nil

    var body: some View {
        if let play = actions.play {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
            }
        }

        if let sectionsExpanded {
            let isExpanded = sectionsExpanded.wrappedValue
            Button {
                withAnimation(AppAnimation.springSnappy) {
                    sectionsExpanded.wrappedValue.toggle()
                }
            } label: {
                Label(
                    isExpanded ? "Hide Sections" : "Show Sections",
                    systemImage: isExpanded ? "list.bullet.indent" : "list.bullet"
                )
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

struct SetlistRowMenuButton<MenuContent: View>: View {
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
