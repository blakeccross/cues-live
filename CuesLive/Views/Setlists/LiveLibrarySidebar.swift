#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// Source list for the live window, laid out like Notes: song folders above setlists.
/// Selecting All Songs or a folder opens the song list beside the sidebar; selecting a
/// setlist closes it and switches to that setlist. Folders and setlists rename in place
/// (Return or Rename…) and delete with the Delete key or the context menu.
@MainActor
struct LiveLibrarySidebar: View {
    enum Item: Hashable {
        case allSongs
        case folder(UUID)
        case setlist(UUID)
    }

    @Binding var selection: Item?
    /// Creates a setlist, makes it active, and returns its ID.
    let onNewSetlist: () -> UUID?
    /// Deletes a setlist, moving playback off it first when it is the active one.
    let onDeleteSetlist: (Setlist) -> Void

    @Environment(\.modelContext) var modelContext
    @Query var songs: [Song]
    @Query var folders: [SongFolder]
    @Query var setlists: [Setlist]

    @State var renamingItem: Item?
    @State var renameText = ""
    @State var itemPendingDelete: Item?
    @State var errorMessage: String?
    @FocusState var isRenameFieldFocused: Bool

    var sortedFolders: [SongFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Sorted by name so rows stay put when opening a setlist bumps its `lastOpenedAt`.
    var sortedSetlists: [Setlist] {
        setlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        sidebarDialogs(on: sidebarList)
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            Section("Songs") {
                Label("All Songs", systemImage: "music.note.house")
                    .badge(songs.count)
                    .tag(Item.allSongs)
                    .dropDestination(for: String.self) { payloads, _ in
                        moveDroppedSongs(payloads, to: nil)
                    }

                ForEach(sortedFolders) { folder in
                    folderRow(folder)
                }
            }

            Section("Setlists") {
                ForEach(sortedSetlists) { setlist in
                    setlistRow(setlist)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 320)
        .onKeyPress(.return) {
            guard renamingItem == nil, let selection, beginRename(of: selection) else { return .ignored }
            return .handled
        }
        .onDeleteCommand {
            guard renamingItem == nil, let selection, selection != .allSongs else { return }
            itemPendingDelete = selection
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            newItemMenu
        }
    }

    private func folderRow(_ folder: SongFolder) -> some View {
        editableLabel(for: .folder(folder.id), title: folder.name, systemImage: "folder")
            .badge(folder.songs.count)
            .tag(Item.folder(folder.id))
            .dropDestination(for: String.self) { payloads, _ in
                moveDroppedSongs(payloads, to: folder)
            }
            .contextMenu {
                Button("Rename", systemImage: "pencil") {
                    beginRename(of: .folder(folder.id))
                }
                Divider()
                Button("Delete Folder…", systemImage: "trash", role: .destructive) {
                    itemPendingDelete = .folder(folder.id)
                }
            }
    }

    private func setlistRow(_ setlist: Setlist) -> some View {
        editableLabel(for: .setlist(setlist.id), title: displayName(for: setlist), systemImage: "music.note.list")
            .badge(setlist.entries.count { $0.song != nil })
            .tag(Item.setlist(setlist.id))
            .contextMenu {
                Button("Rename", systemImage: "pencil") {
                    beginRename(of: .setlist(setlist.id))
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
                    itemPendingDelete = .setlist(setlist.id)
                }
            }
    }

    /// The row's title, or a focused text field while that row is being renamed.
    private func editableLabel(for item: Item, title: String, systemImage: String) -> some View {
        Label {
            if renamingItem == item {
                TextField("Name", text: $renameText)
                    .focused($isRenameFieldFocused)
                    .onSubmit { commitRename(of: item) }
                    .onExitCommand { renamingItem = nil }
                    .onChange(of: isRenameFieldFocused) { _, isFocused in
                        if !isFocused { commitRename(of: item) }
                    }
                    .task { isRenameFieldFocused = true }
            } else {
                Text(title)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private var newItemMenu: some View {
        Menu {
            Button("New Folder", systemImage: "folder.badge.plus", action: createFolder)
            Button("New Setlist", systemImage: "music.note.list", action: createSetlist)
        } label: {
            Label("New", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .help("New folder or setlist")
    }

    func displayName(for setlist: Setlist) -> String {
        let trimmed = setlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Setlist" : trimmed
    }
}
#endif
