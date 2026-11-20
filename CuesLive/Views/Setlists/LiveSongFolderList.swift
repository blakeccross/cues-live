#if os(macOS)
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The folder column of the song browser: All Songs above the user's song folders. Folders
/// rename in place (Return or Rename…), delete with the Delete key or the context menu, and take
/// songs dragged onto them.
///
/// Song drops are handled once for the whole list rather than per row: drop targets on sidebar
/// rows only cover part of the row and drift away from the cursor. The list resolves the row
/// under the cursor from each row's measured frame instead.
@MainActor
struct LiveSongFolderList: View {
    enum Item: Hashable {
        case allSongs
        case folder(UUID)
    }

    /// How far past a row's content the row still counts as under the cursor, so the gap
    /// between rows is not a dead zone.
    private static let dropRowSlack: CGFloat = AppSpacing.compact

    @Binding var selection: Item?

    @Environment(\.modelContext) private var modelContext
    @Query private var songs: [Song]
    @Query private var folders: [SongFolder]

    @State private var renamingFolderID: UUID?
    @State private var renameText = ""
    @State private var folderPendingDelete: SongFolder?
    @State private var errorMessage: String?
    @State private var listFrame: CGRect = .zero
    @State private var rowFrames: [Item: CGRect] = [:]
    @State private var dropTarget: Item?
    @FocusState private var isRenameFieldFocused: Bool

    private var sortedFolders: [SongFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        folderDialogs(on: folderList)
    }

    private var folderList: some View {
        List(selection: $selection) {
            Label("All Songs", systemImage: "music.note.house")
                .songDropRow(.allSongs, target: dropTarget, frames: $rowFrames)
                .badge(songs.count)
                .tag(Item.allSongs)

            ForEach(sortedFolders) { folder in
                folderRow(folder)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            listFrame = frame
        }
        .onDrop(of: [.plainText], delegate: SongFolderListDropDelegate(
            target: { location in dropRow(at: location) },
            onTargetChange: { dropTarget = $0 },
            onPerform: { item, providers in performSongDrop(providers, on: item) }
        ))
        .onKeyPress(.return) {
            guard renamingFolderID == nil, case .folder(let id) = selection else { return .ignored }
            beginRename(of: id)
            return .handled
        }
        .onDeleteCommand {
            guard renamingFolderID == nil, case .folder(let id) = selection else { return }
            folderPendingDelete = folders.first { $0.id == id }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            newFolderButton
        }
    }

    private func folderRow(_ folder: SongFolder) -> some View {
        Label {
            if renamingFolderID == folder.id {
                TextField("Name", text: $renameText)
                    .focused($isRenameFieldFocused)
                    .onSubmit { commitRename(of: folder) }
                    .onExitCommand { renamingFolderID = nil }
                    .onChange(of: isRenameFieldFocused) { _, isFocused in
                        if !isFocused { commitRename(of: folder) }
                    }
                    .task { isRenameFieldFocused = true }
            } else {
                Text(folder.name)
            }
        } icon: {
            Image(systemName: "folder")
        }
        .songDropRow(.folder(folder.id), target: dropTarget, frames: $rowFrames)
        .badge(folder.songs.count)
        .tag(Item.folder(folder.id))
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                beginRename(of: folder.id)
            }
            Divider()
            Button("Delete Folder…", systemImage: "trash", role: .destructive) {
                folderPendingDelete = folder
            }
        }
    }

    private var newFolderButton: some View {
        Button(action: createFolder) {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .help("New song folder")
    }

    private func beginRename(of id: UUID, currentName: String? = nil) {
        guard let name = currentName ?? folders.first(where: { $0.id == id })?.name else { return }
        renameText = name
        renamingFolderID = id
    }

    private func commitRename(of folder: SongFolder) {
        guard renamingFolderID == folder.id else { return }
        renamingFolderID = nil
        do {
            try SongFolderStore.rename(folder, to: renameText, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFolder() {
        do {
            let folder = try SongFolderStore.create(
                existingNames: Set(folders.map(\.name)),
                context: modelContext
            )
            selection = .folder(folder.id)
            beginRename(of: folder.id, currentName: folder.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ folder: SongFolder) {
        folderPendingDelete = nil
        if selection == .folder(folder.id) {
            selection = .allSongs
        }
        do {
            try SongFolderStore.delete(folder, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The row under a drop location given in the list's own coordinates.
    private func dropRow(at location: CGPoint) -> Item? {
        let y = listFrame.minY + location.y
        return rowFrames
            .filter { _, frame in
                y >= frame.minY - Self.dropRowSlack && y <= frame.maxY + Self.dropRowSlack
            }
            .min { abs($0.value.midY - y) < abs($1.value.midY - y) }?
            .key
    }

    private func performSongDrop(_ providers: [NSItemProvider], on item: Item) {
        Task {
            let ids = await SongDragPayload.songIDs(from: providers)
            moveDroppedSongs(Set(ids), to: item)
        }
    }

    /// Dropping on a folder moves songs into it; dropping on All Songs takes them out of folders.
    private func moveDroppedSongs(_ ids: Set<UUID>, to item: Item) {
        let dropped = songs.filter { ids.contains($0.id) }
        guard !dropped.isEmpty else { return }
        let folder: SongFolder?
        switch item {
        case .allSongs:
            folder = nil
        case .folder(let id):
            guard let match = folders.first(where: { $0.id == id }) else { return }
            folder = match
        }
        do {
            try SongFolderStore.move(dropped, to: folder, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func folderDialogs<Content: View>(on content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete Folder?",
                isPresented: Binding(
                    get: { folderPendingDelete != nil },
                    set: { if !$0 { folderPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: folderPendingDelete
            ) { folder in
                Button("Delete Folder", role: .destructive) {
                    delete(folder)
                }
            } message: { folder in
                Text("\"\(folder.name)\" will be deleted. Its songs stay in All Songs.")
            }
            .alert("Could Not Update Library", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

/// Routes a song drag over the folder list to whichever row is under the cursor.
private struct SongFolderListDropDelegate: DropDelegate {
    let target: (CGPoint) -> LiveSongFolderList.Item?
    let onTargetChange: (LiveSongFolderList.Item?) -> Void
    let onPerform: (LiveSongFolderList.Item, [NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let item = target(info.location)
        onTargetChange(item)
        return DropProposal(operation: item == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        onTargetChange(nil)
        guard let item = target(info.location) else { return false }
        onPerform(item, info.itemProviders(for: [.plainText]))
        return true
    }
}

private extension View {
    /// Spans the full row width, reports the row's frame for drop hit-testing, and outlines
    /// the row while a song drag is over it.
    func songDropRow(
        _ item: LiveSongFolderList.Item,
        target: LiveSongFolderList.Item?,
        frames: Binding<[LiveSongFolderList.Item: CGRect]>
    ) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                frames.wrappedValue[item] = frame
            }
            .onDisappear {
                frames.wrappedValue[item] = nil
            }
            .overlay {
                if target == item {
                    RoundedRectangle(cornerRadius: AppRadius.xxs)
                        .stroke(AppColors.accent, lineWidth: 2)
                        .padding(.horizontal, -AppSpacing.xxs)
                        .allowsHitTesting(false)
                }
            }
    }
}

#endif
