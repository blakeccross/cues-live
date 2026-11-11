import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension LivePlaybackView {
    func importSongs(from requests: [SongFolderImporter.ImportRequest]) {
        guard !isImportingSongFolder, !requests.isEmpty else { return }

        isImportingSongFolder = true
        Task { @MainActor in
            defer { isImportingSongFolder = false }

            var importedSongs: [Song] = []
            var summaries: [String] = []
            var failureMessages: [String] = []

            for request in requests {
                do {
                    let importResult = try SongFolderImporter.importFromFolder(
                        at: request.folderURL,
                        settings: request.settings,
                        context: modelContext
                    )
                    importedSongs.append(importResult.song)
                    summaries.append(SongFolderImporter.summaryMessage(for: importResult))
                } catch {
                    let label = request.settings.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    failureMessages.append(
                        requests.count == 1
                            ? error.localizedDescription
                            : "\(label.isEmpty ? request.folderURL.lastPathComponent : label): \(error.localizedDescription)"
                    )
                }
            }

            if !failureMessages.isEmpty {
                songImportFeedback = .failure(failureMessages.joined(separator: "\n"))
            } else if let song = importedSongs.first, importedSongs.count == 1 {
                // One new song: open it in the editor to get it ready, rather than confirming in an alert.
                presentSongEditor(for: song)
            } else {
                songImportFeedback = .success("Imported \(summaries.count) songs.")
            }
        }
    }

    var setlistSaveFileName: String {
        let raw = (activeSetlist?.name ?? "Setlist")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = (raw.isEmpty || raw.caseInsensitiveCompare(Setlist.untitledName) == .orderedSame
            ? "Setlist"
            : raw)
            .components(separatedBy: invalid)
            .joined(separator: "-")
        return cleaned
    }

    var setlistPackageExportFileName: String {
        let raw = (activeSetlist?.name ?? "Setlist")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = (raw.isEmpty ? "Setlist" : raw)
            .components(separatedBy: invalid)
            .joined(separator: "-")
        return cleaned
    }

    func presentExportSetlistPackage() {
        guard activeSetlist != nil else { return }
        #if os(macOS)
        presentExportSetlistFolderMac()
        #else
        presentExportSetlistFolderExporter()
        #endif
    }

    #if os(macOS)
    private func presentExportSetlistFolderMac() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Export Setlist Folder"
        panel.message = "Creates a folder with the show file and a Songs folder."
        panel.nameFieldStringValue = setlistPackageExportFileName
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try SetlistPackageStore.export(
                setlist: workingSetlist,
                to: url,
                context: modelContext
            )
            songImportFeedback = .success("Exported setlist folder with songs, stems, clicks, and headers.")
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }
    #endif

    private func presentExportSetlistFolderExporter() {
        do {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("MTLExport-\(UUID().uuidString)", isDirectory: true)
            let packageURL = staging.appendingPathComponent(
                setlistPackageExportFileName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try SetlistPackageStore.export(
                setlist: workingSetlist,
                to: packageURL,
                context: modelContext
            )
            setlistPackageDocument = try SetlistPackageFileDocument(packageDirectory: packageURL)
            showingSetlistPackageExporter = true
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    func handleSetlistPackageExportResult(_ result: Result<URL, Error>) {
        setlistPackageDocument = nil
        switch result {
        case .success:
            songImportFeedback = .success("Exported setlist folder with songs, stems, clicks, and headers.")
        case .failure(let error):
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    func handleShowFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            songImportFeedback = .failure(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            openShowFile(at: url)
        }
    }

    func presentOpen() {
        #if os(macOS)
        DispatchQueue.main.async {
            presentOpenSetlistPanel()
        }
        #else
        showingShowFileImporter = true
        #endif
    }

    #if os(macOS)
    private func presentOpenSetlistPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Open Setlist"
        panel.message = "Choose a cues.live setlist file (.cueshow)."
        panel.prompt = "Open"
        panel.allowedContentTypes = [ProjectUTType.showProjectType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openShowFile(at: url)
    }
    #endif

    private func openShowFile(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let setlist = try SongProjectBridge.importShow(from: url, into: modelContext)
            activateOpenedSetlist(setlist)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func activateOpenedSetlist(_ setlist: Setlist) {
        if setlist.id == activeSetlistID {
            clearMarkerCue()
            sectionLoop.reset()
            groupMixFade.cancel()
            coordinator.stop()
            markSetlistOpened(setlist)
            coordinator.configure(setlist: setlist)
            ignoredMissingMediaPromptForSetlistID = nil
            promptForMissingMediaIfNeeded(in: setlist)
        } else {
            ignoredMissingMediaPromptForSetlistID = nil
            switchToSetlist(setlist)
        }
    }

    func presentSave() {
        guard let setlist = activeSetlist else { return }
        if setlist.isDraft || setlist.showFilePath == nil {
            presentSaveLocationPicker(isSaveAs: false)
        } else {
            saveSetlistInPlace()
        }
    }

    func presentSaveAs() {
        guard activeSetlist != nil else { return }
        presentSaveLocationPicker(isSaveAs: true)
    }

    private func presentSaveLocationPicker(isSaveAs: Bool) {
        #if os(macOS)
        DispatchQueue.main.async {
            presentSaveSetlistPanel(isSaveAs: isSaveAs)
        }
        #else
        presentSaveSetlistExporter()
        #endif
    }

    #if os(macOS)
    private func presentSaveSetlistPanel(isSaveAs: Bool) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = isSaveAs ? "Save Setlist As" : "Save Setlist"
        panel.message = "Choose a name and location for this setlist."
        panel.nameFieldLabel = "Name:"
        panel.nameFieldStringValue = setlistSaveFileName
        panel.allowedContentTypes = [ProjectUTType.showProjectType]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.prompt = "Save"
        if !isSaveAs {
            panel.directoryURL = ShowFileStore.showsDirectory
        } else if let path = activeSetlist?.showFilePath {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        commitSave(to: url)
    }
    #endif

    private func presentSaveSetlistExporter() {
        guard let setlist = activeSetlist else { return }
        do {
            let data = try SongProjectBridge.encodedShowData(for: setlist, context: modelContext)
            showFileDocument = ShowFileDocument(data: data)
            showingShowFileExporter = true
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    func handleShowFileExportResult(_ result: Result<URL, Error>) {
        showFileDocument = nil
        switch result {
        case .success(let url):
            commitSave(to: url)
        case .failure(let error):
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func commitSave(to url: URL) {
        guard let setlist = activeSetlist else { return }
        setlist.name = ShowFileStore.displayName(fromShowURL: url)
        setlist.isDraft = false
        do {
            try modelContext.save()
            try SongProjectBridge.persistShow(for: setlist, to: url, context: modelContext)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    private func saveSetlistInPlace() {
        guard let setlist = activeSetlist else { return }
        do {
            try modelContext.save()
            try SongProjectBridge.persistShow(for: setlist, context: modelContext)
        } catch {
            songImportFeedback = .failure(error.localizedDescription)
        }
    }

    func createUntitledSetlist() {
        let newSetlist = Setlist.untitledDraft()
        modelContext.insert(newSetlist)
        try? modelContext.save()
        switchToSetlist(newSetlist)
    }
}
