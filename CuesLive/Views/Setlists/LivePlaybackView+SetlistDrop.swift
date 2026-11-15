import SwiftUI

extension LivePlaybackView {
    /// Handles a drop on the setlist at `rowIndex`. Library songs are inserted directly; Finder
    /// folders go through the song setup sheet, are imported into the library, then inserted.
    /// Returns whether the drop was accepted.
    @discardableResult
    func performSetlistDrop(at rowIndex: Int, providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        guard !SongFolderDrop.containsFileURLs(providers) else {
            guard !isImportingSongFolder, setlistFolderSetupSession == nil else { return false }
            Task { @MainActor in
                await prepareSetlistFolderImport(from: providers, at: rowIndex)
            }
            return true
        }

        Task { @MainActor in
            let ids = await SongDragPayload.songIDs(from: providers)
            insertDroppedSongs(at: rowIndex, songIDs: ids)
        }
        return true
    }

    private func prepareSetlistFolderImport(from providers: [NSItemProvider], at rowIndex: Int) async {
        let folderURLs = await SongFolderDrop.folderURLs(from: providers)
        guard !folderURLs.isEmpty else {
            songImportFeedback = .failure("Drop a folder containing audio files to add a song.")
            return
        }

        let (previews, failures) = await SongFolderDrop.previews(for: folderURLs)
        if !failures.isEmpty {
            songImportFeedback = .failure(failures.joined(separator: "\n"))
        }
        guard !previews.isEmpty else { return }
        setlistFolderSetupSession = SongFolderSetupSession(previews: previews, setlistRowIndex: rowIndex)
    }
}
