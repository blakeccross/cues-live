import SwiftUI
import UniformTypeIdentifiers

/// A plain native list. Click or tap selects (Command/Shift-click or iOS Edit mode for several rows),
/// double-click or double-tap cues a song (stopped, at its start), and dragging a selected row moves the whole selection.
/// Row actions are shared by the context menu, the trailing "…" button and iOS swipe actions.
struct SetlistListView: View {
    let rows: [SetlistRowModel]
    let currentIndex: Int
    let isPlaying: Bool
    @Binding var isEditing: Bool
    let actions: (SetlistRowModel) -> SetlistRowActions
    let onMove: (IndexSet, Int) -> Void
    /// Removes the rows with these IDs, given in list order.
    let onRemove: ([AnyHashable]) -> Void
    var onAddHeader: (() -> Void)? = nil
    /// Called with the row index to insert at when library songs or Finder folders are dropped on the list.
    var onDropItems: ((Int, [NSItemProvider]) -> Void)? = nil
    /// Enables expandable section lists under song rows.
    var sectionPlayback: SetlistSectionPlayback? = nil
    /// Inset of row content from the list's edges. Rows are padded rather than the list,
    /// so the scroller stays at the edge.
    var rowHorizontalPadding: CGFloat = 0

    /// Library song drags, plus Finder folders on macOS, which are imported as new songs.
    static var dropTypes: [UTType] {
        #if os(macOS)
        [.plainText, .fileURL]
        #else
        [.plainText]
        #endif
    }

    /// Rows the user expanded or collapsed by hand; others follow the current song.
    @State var expansionOverrides: [AnyHashable: Bool] = [:]
    @State var selection: Set<AnyHashable> = []
    /// Rows waiting on the confirmation shown before removing more than one at once.
    @State var rowsPendingRemoval: [AnyHashable] = []

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                rowView(row)
            }
            .onMove(perform: moveRows)
            .onInsert(of: onDropItems == nil ? [] : Self.dropTypes) { index, providers in
                onDropItems?(index, providers)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(AppAnimation.springSmooth, value: currentIndex)
        .onChange(of: currentIndex) { _, _ in
            expansionOverrides.removeAll()
        }
        .selectionContextMenu(menu: selectionMenu(for:), primaryAction: cueSelection(_:))
        .selectionCommands(onDelete: removeSelection, onClear: { selection.removeAll() })
        .onChange(of: rows.map(\.id)) { _, ids in
            selection.formIntersection(ids)
        }
        .onChange(of: isEditing) { _, _ in
            selection.removeAll()
        }
        .removalConfirmation(rows: $rowsPendingRemoval, perform: confirmRemoval(of:))
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                SetlistSelectionBar(count: selection.count, onRemove: removeSelection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
                menu: { SetlistRowMenuContent(model: row, actions: rowActions, remove: { requestRemoval(of: [row.id]) }) }
            )
            .padding(.horizontal, rowHorizontalPadding)
            .listRowSeparator(.hidden)
            .listRowBackground(rowBackground(for: row, base: AppColors.headerBand))
            .nativeSelectionHighlightHidden()
            .setlistSwipeActions(actions: rowActions, remove: { requestRemoval(of: [row.id]) })

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
        let remove = { requestRemoval(of: [row.id]) }
        return VStack(spacing: 0) {
            SetlistSongRowView(
                song: song,
                isCurrent: isCurrent,
                isFinished: song.playbackIndex < currentIndex,
                isPlaying: isPlaying,
                showsMenu: !isEditing,
                menu: { SetlistRowMenuContent(model: row, actions: rowActions, sectionsExpanded: expansion, remove: remove) }
            )
            .contentShape(Rectangle())
            .setlistRowSelectionGestures(
                isEnabled: !isEditing,
                select: { select(row) },
                cue: { rowActions.cue?() }
            )
            .accessibilityAction(named: "Cue") { rowActions.cue?() }
            .mappableLiveControl(.goToSong(song.playbackIndex), cornerRadius: AppRadius.sm)

            if let sectionPlayback, expansion?.wrappedValue == true {
                SetlistSectionGridView(
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
        .listRowBackground(rowBackground(for: row, base: Color.clear))
        .nativeSelectionHighlightHidden()
        .setlistSwipeActions(actions: rowActions, remove: remove)
    }

    /// Selection is drawn here rather than by the list: iOS hides its own highlight behind custom
    /// row backgrounds, and macOS's is turned off so both platforms share one color.
    private func rowBackground(for row: SetlistRowModel, base: Color) -> Color {
        selection.contains(row.id) ? AppColors.rowSelection : base
    }

    /// Nil when the row can't expand. Otherwise a manual override wins, and the current song
    /// opens by default.
    func expansionBinding(for row: SetlistRowModel, song: SetlistRowModel.Song) -> Binding<Bool>? {
        guard sectionPlayback != nil, !isEditing, !song.sections.isEmpty else { return nil }
        let isCurrent = song.playbackIndex == currentIndex
        return Binding(
            get: { expansionOverrides[row.id] ?? isCurrent },
            set: { expansionOverrides[row.id] = $0 }
        )
    }
}

private extension View {
    @ViewBuilder
    func nativeSelectionHighlightHidden() -> some View {
        #if os(macOS)
        listSelectionHighlightHidden()
        #else
        self
        #endif
    }

    /// Swipe to cue (leading) or remove / edit (trailing). iOS only; macOS uses the menu.
    @ViewBuilder
    func setlistSwipeActions(actions: SetlistRowActions, remove: @escaping () -> Void) -> some View {
        #if os(iOS)
        self
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let cue = actions.cue {
                    Button(action: cue) {
                        Label("Cue", systemImage: "forward.end.fill")
                    }
                    .tint(AppColors.accent)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: remove) {
                    Label("Remove", systemImage: "trash")
                }
                if let edit = actions.edit {
                    Button(action: edit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(AppColors.info)
                }
            }
        #else
        self
        #endif
    }
}
