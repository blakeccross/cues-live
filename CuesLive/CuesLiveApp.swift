import SwiftData
import SwiftUI

#if os(macOS)
private enum AppWindowMetrics {
    static let minimumWidth: CGFloat = 960
    static let minimumHeight: CGFloat = 600
    static let defaultWidth: CGFloat = 1280
    static let defaultHeight: CGFloat = 800
}
#endif

@main
struct CuesLiveApp: App {
    private let modelContainer: ModelContainer
    #if os(macOS)
    private let sparkleUpdater = SparkleUpdater()
    #endif
    #if os(iOS)
    @UIApplicationDelegateAdaptor(CuesLiveAppDelegate.self) private var appDelegate
    #endif

    init() {
        do {
            modelContainer = try PersistenceController.makeContainer()
        } catch {
            fatalError("Could not initialize app storage: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(macOS)
                .frame(
                    minWidth: AppWindowMetrics.minimumWidth,
                    minHeight: AppWindowMetrics.minimumHeight
                )
                #endif
                .preferredColorScheme(.dark)
                .environment(InputMappingController.shared)
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(
            width: AppWindowMetrics.defaultWidth,
            height: AppWindowMetrics.defaultHeight
        )
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.expanded)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: sparkleUpdater.updater)
            }
            FileMenuCommands()
            SongMenuCommands()
            SongUndoCommands()
            ClipEditorCommands()
            LiveMappingCommands()
            HelpMenuCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            AppSettingsView(updater: sparkleUpdater.updater)
                .modelContainer(modelContainer)
                .environment(InputMappingController.shared)
        }

        Window("cues.live Help", id: DocsWindowID.value) {
            DocsWindowView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 780, height: 560)
        #endif
    }
}

struct SongEditorActions {
    var canAutoGroup = false
    var autoGroup: () -> Void = {}
    var importAbleton: () -> Void = {}
}

struct ClipEditorActions {
    var canSplit = false
    var canJoin = false
    var split: () -> Void = {}
    var join: () -> Void = {}
}

struct SongUndoActions {
    var canUndo = false
    var canRedo = false
    var undoActionName: String?
    var redoActionName: String?
    var undo: () -> Void = {}
    var redo: () -> Void = {}
}

private struct SongEditorActionsKey: FocusedValueKey {
    typealias Value = SongEditorActions
    static var defaultValue: Value? { nil }
}

private struct ClipEditorActionsKey: FocusedValueKey {
    typealias Value = ClipEditorActions
    static var defaultValue: Value? { nil }
}

private struct SongUndoActionsKey: FocusedValueKey {
    typealias Value = SongUndoActions
    static var defaultValue: Value? { nil }
}

extension FocusedValues {
    var songEditorActions: SongEditorActions? {
        get { self[SongEditorActionsKey.self] }
        set { self[SongEditorActionsKey.self] = newValue }
    }

    var clipEditorActions: ClipEditorActions? {
        get { self[ClipEditorActionsKey.self] }
        set { self[ClipEditorActionsKey.self] = newValue }
    }

    var songUndoActions: SongUndoActions? {
        get { self[SongUndoActionsKey.self] }
        set { self[SongUndoActionsKey.self] = newValue }
    }
}

#if os(macOS)
struct FileMenuCommands: Commands {
    @Bindable private var menu = LiveSetlistMenuController.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                menu.newSetlist()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!menu.canNew)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Open…") {
                menu.open()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!menu.canOpen)

            Divider()

            Button("Save") {
                menu.save()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!menu.canSave)

            Button("Save As…") {
                menu.saveAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!menu.canSave)

            Button("Export Setlist Folder…") {
                menu.exportPackage()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!menu.canExportPackage)
        }
    }
}

struct SongMenuCommands: Commands {
    @FocusedValue(\.songEditorActions) private var actions

    var body: some Commands {
        CommandMenu("Song") {
            Button("Auto Group") {
                actions?.autoGroup()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(actions?.canAutoGroup != true)

            Button("Add Ableton File…") {
                actions?.importAbleton()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }
    }
}

struct SongUndoCommands: Commands {
    @FocusedValue(\.songUndoActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(actions?.undoActionName.map { "Undo \($0)" } ?? "Undo") {
                actions?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(actions?.canUndo != true)

            Button(actions?.redoActionName.map { "Redo \($0)" } ?? "Redo") {
                actions?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(actions?.canRedo != true)
        }
    }
}

struct ClipEditorCommands: Commands {
    @FocusedValue(\.clipEditorActions) private var actions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Split at Edit Point") {
                actions?.split()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(actions?.canSplit != true)

            Button("Join with Next Region") {
                actions?.join()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(actions?.canJoin != true)
        }
    }
}

struct LiveMappingCommands: Commands {
    @Bindable private var mapping = InputMappingController.shared

    var body: some Commands {
        CommandMenu("Controls") {
            Button(mapping.session == .keyMapping ? "Done Key Mapping" : "Key Mapping") {
                mapping.toggleKeyMapping()
            }

            Button(mapping.session == .midiMapping ? "Done MIDI Mapping" : "MIDI Mapping") {
                mapping.toggleMIDIMapping()
            }
        }
    }
}

struct HelpMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("cues.live Help") {
                openWindow(id: DocsWindowID.value)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
#endif
