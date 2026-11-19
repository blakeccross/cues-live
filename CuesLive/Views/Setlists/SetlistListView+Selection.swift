import SwiftUI

extension SetlistListView {
    /// Selected row IDs in list order, so bulk actions act top to bottom.
    func orderedIDs(_ ids: Set<AnyHashable>) -> [AnyHashable] {
        rows.map(\.id).filter(ids.contains)
    }

    func select(_ row: SetlistRowModel) {
        selection = [row.id]
    }

    /// Dragging any selected row carries the whole selection with it.
    func moveRows(from source: IndexSet, to destination: Int) {
        let selectedOffsets = IndexSet(rows.indices.filter { selection.contains(rows[$0].id) })
        let moved = source.isSubset(of: selectedOffsets) ? selectedOffsets : source
        onMove(moved, destination)
    }

    /// Double-click (macOS) cues a song when it is the only row clicked or selected.
    func cueSelection(_ ids: Set<AnyHashable>) {
        guard ids.count == 1,
              let row = rows.first(where: { $0.id == ids.first }),
              case .song = row.kind else {
            return
        }
        actions(row).cue?()
    }

    func removeSelection() {
        requestRemoval(of: orderedIDs(selection))
    }

    /// Removes one row straight away; more than one waits for confirmation.
    func requestRemoval(of ids: [AnyHashable]) {
        guard !ids.isEmpty else { return }
        if ids.count > 1 {
            rowsPendingRemoval = ids
        } else {
            confirmRemoval(of: ids)
        }
    }

    func confirmRemoval(of ids: [AnyHashable]) {
        selection.subtract(ids)
        onRemove(ids)
    }

    /// Empty space offers Add Header, one row its own menu, and a multi-row selection bulk removal.
    @ViewBuilder
    func selectionMenu(for ids: Set<AnyHashable>) -> some View {
        if ids.isEmpty {
            if let onAddHeader {
                Button(action: onAddHeader) {
                    Label("Add Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
            }
        } else if ids.count == 1, let row = rows.first(where: { $0.id == ids.first }) {
            SetlistRowMenuContent(
                model: row,
                actions: actions(row),
                sectionsExpanded: sectionsExpansion(for: row),
                remove: { requestRemoval(of: [row.id]) }
            )
        } else if ids.count > 1 {
            Button(role: .destructive) {
                requestRemoval(of: orderedIDs(ids))
            } label: {
                Label("Remove \(ids.count) Items from Setlist", systemImage: "trash")
            }
        }
    }

    private func sectionsExpansion(for row: SetlistRowModel) -> Binding<Bool>? {
        guard case .song(let song) = row.kind else { return nil }
        return expansionBinding(for: row, song: song)
    }
}

extension View {
    /// The list-wide context menu, plus double-click to act on macOS. iOS keeps a single tap for
    /// selection, so its double-tap comes from `setlistRowSelectionGestures` instead.
    func selectionContextMenu<Menu: View>(
        @ViewBuilder menu: @escaping (Set<AnyHashable>) -> Menu,
        primaryAction: @escaping (Set<AnyHashable>) -> Void
    ) -> some View {
        #if os(macOS)
        contextMenu(forSelectionType: AnyHashable.self, menu: menu, primaryAction: primaryAction)
        #else
        contextMenu(forSelectionType: AnyHashable.self, menu: menu)
        #endif
    }

    /// Delete removes the selection and Escape clears it. macOS only; iOS uses the selection bar.
    @ViewBuilder
    func selectionCommands(onDelete: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        #if os(macOS)
        onDeleteCommand(perform: onDelete)
            .onExitCommand(perform: onClear)
        #else
        self
        #endif
    }

    /// iOS rows: tap selects and double-tap cues. Off in Edit mode, where the list's own tap
    /// toggles the checkmark. macOS gets both from the list itself.
    @ViewBuilder
    func setlistRowSelectionGestures(
        isEnabled: Bool,
        select: @escaping () -> Void,
        cue: @escaping () -> Void
    ) -> some View {
        #if os(iOS)
        gesture(
            TapGesture(count: 2).onEnded(cue)
                .exclusively(before: TapGesture().onEnded(select)),
            including: isEnabled ? .all : .subviews
        )
        #else
        self
        #endif
    }

    /// Asks before removing several rows at once.
    func removalConfirmation(
        rows: Binding<[AnyHashable]>,
        perform: @escaping ([AnyHashable]) -> Void
    ) -> some View {
        let count = rows.wrappedValue.count
        return confirmationDialog(
            "Remove \(count) items from the setlist?",
            isPresented: Binding(
                get: { !rows.wrappedValue.isEmpty },
                set: { if !$0 { rows.wrappedValue = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove \(count) Items", role: .destructive) {
                let ids = rows.wrappedValue
                rows.wrappedValue = []
                perform(ids)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The songs stay in your library.")
        }
    }
}
