#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// Source list of setlists for the live window. Selecting a setlist switches playback to it.
/// Setlists rename in place (Return or Rename…) and delete with the Delete key or the context
/// menu. Song folders live in the song browser instead.
@MainActor
struct LiveLibrarySidebar: View {
    /// The selected setlist's ID.
    @Binding var selection: UUID?
    /// Creates a setlist, makes it active, and returns its ID.
    let onNewSetlist: () -> UUID?
    /// Deletes a setlist, moving playback off it first when it is the active one.
    let onDeleteSetlist: (Setlist) -> Void

    @Environment(\.modelContext) var modelContext
    @Query var setlists: [Setlist]

    @State var renamingSetlistID: UUID?
    @State var renameText = ""
    @State var setlistPendingDelete: Setlist?
    @State var errorMessage: String?
    @FocusState var isRenameFieldFocused: Bool

    /// Sorted by name so rows stay put when opening a setlist bumps its `lastOpenedAt`.
    var sortedSetlists: [Setlist] {
        setlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        sidebarDialogs(on: sidebarList)
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            Section("Setlists") {
                ForEach(sortedSetlists) { setlist in
                    setlistRow(setlist)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 320)
        .onKeyPress(.return) {
            guard renamingSetlistID == nil, let selection else { return .ignored }
            beginRename(of: selection)
            return .handled
        }
        .onDeleteCommand {
            guard renamingSetlistID == nil, let selection else { return }
            setlistPendingDelete = setlist(id: selection)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            newSetlistButton
        }
    }

    private func setlistRow(_ setlist: Setlist) -> some View {
        editableLabel(for: setlist)
            .badge(setlist.entries.count { $0.song != nil })
            .tag(setlist.id)
            .contextMenu {
                Button("Rename", systemImage: "pencil") {
                    beginRename(of: setlist.id)
                }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    duplicate(setlist)
                }
                if let path = setlist.showFilePath {
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
                Divider()
                Button("Delete Setlist…", systemImage: "trash", role: .destructive) {
                    setlistPendingDelete = setlist
                }
            }
    }

    /// The row's title, or a focused text field while that row is being renamed.
    private func editableLabel(for setlist: Setlist) -> some View {
        Label {
            if renamingSetlistID == setlist.id {
                TextField("Name", text: $renameText)
                    .focused($isRenameFieldFocused)
                    .onSubmit { commitRename(of: setlist.id) }
                    .onExitCommand { renamingSetlistID = nil }
                    .onChange(of: isRenameFieldFocused) { _, isFocused in
                        if !isFocused { commitRename(of: setlist.id) }
                    }
                    .task { isRenameFieldFocused = true }
            } else {
                Text(displayName(for: setlist))
            }
        } icon: {
            Image(systemName: "music.note.list")
        }
    }

    private var newSetlistButton: some View {
        Button(action: createSetlist) {
            Label("New Setlist", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .help("New setlist")
    }

    func displayName(for setlist: Setlist) -> String {
        let trimmed = setlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Setlist" : trimmed
    }
}
#endif
