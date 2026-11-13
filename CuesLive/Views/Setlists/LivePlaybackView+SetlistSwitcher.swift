import SwiftUI

extension LivePlaybackView {
    func setlistDisplayName(for setlist: Setlist) -> String {
        let trimmed = setlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Setlist" : trimmed
    }

    @ViewBuilder
    func setlistSwitcherMenuContent() -> some View {
        ForEach(allSetlists) { candidate in
            Button {
                switchToSetlist(candidate)
            } label: {
                if candidate.id == activeSetlistID {
                    Label {
                        Text("\(candidate.name) · \(candidate.entries.count) songs")
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                } else {
                    Text("\(candidate.name) · \(candidate.entries.count) songs")
                }
            }
        }

        Divider()

        Button {
            createUntitledSetlist()
        } label: {
            Label("New Setlist", systemImage: "plus")
        }

        Button {
            presentOpen()
        } label: {
            Label("Open…", systemImage: "folder")
        }

        Button {
            presentSave()
        } label: {
            Label("Save", systemImage: "tray.and.arrow.down")
        }

        Button {
            presentSaveAs()
        } label: {
            Label("Save As…", systemImage: "square.and.arrow.down.on.square")
        }

        Button {
            presentExportSetlistPackage()
        } label: {
            Label("Export Setlist Folder…", systemImage: "square.and.arrow.up")
        }
    }

    #if !os(macOS)
    func setlistSwitcherMenu(for setlist: Setlist) -> some View {
        Menu {
            setlistSwitcherMenuContent()
        } label: {
            Text(setlistDisplayName(for: setlist))
                .fontWeight(.semibold)
        }
    }
    #endif
}
