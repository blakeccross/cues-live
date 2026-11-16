#if os(macOS)
import SwiftUI

/// Window menu items that open the app's single-instance windows.
struct WindowMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Song Editor") {
                openWindow(id: SetlistSongEditorWindowID.value)
            }
            .keyboardShortcut("e", modifiers: [.command, .option])

            Button("Video") {
                openWindow(id: VideoWindowID.value)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Divider()
        }
    }
}
#endif
