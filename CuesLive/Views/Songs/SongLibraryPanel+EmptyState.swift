import SwiftUI

extension SongLibraryPanel {
    @ViewBuilder
    var scopeEmptyState: some View {
        switch scope {
        case .allSongs:
            emptyState(
                title: "No Songs Yet",
                systemImage: "music.note.list",
                description: "Import a folder of stems, drop one here, or add a click track."
            )
        case .folder:
            emptyState(
                title: "Empty Folder",
                systemImage: "folder",
                description: "Drag songs onto this folder in the sidebar, or use Move to Folder."
            )
        }
    }

    func emptyState(title: String, systemImage: String, description: String) -> some View {
        VStack(spacing: 0) {
            AppEmptyState(title: title, systemImage: systemImage, description: description)
                .padding(.top, AppSpacing.sm)
            Spacer(minLength: 0)
        }
    }
}
