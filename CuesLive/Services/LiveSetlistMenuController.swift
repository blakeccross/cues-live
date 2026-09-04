#if os(macOS)
import SwiftUI

/// Publishes live setlist file-menu state for the macOS menu bar.
/// `FocusedValue` is unreliable on the setlist screen when no child view holds keyboard focus.
@Observable
final class LiveSetlistMenuController {
    static let shared = LiveSetlistMenuController()

    var canSave = false
    var canNew = false
    var canOpen = false
    var canExportPackage = false

    private var saveHandler: () -> Void = {}
    private var saveAsHandler: () -> Void = {}
    private var newSetlistHandler: () -> Void = {}
    private var openHandler: () -> Void = {}
    private var exportPackageHandler: () -> Void = {}

    private init() {}

    func update(
        canSave: Bool,
        save: @escaping () -> Void,
        saveAs: @escaping () -> Void,
        canNew: Bool,
        newSetlist: @escaping () -> Void,
        canOpen: Bool,
        open: @escaping () -> Void,
        canExportPackage: Bool,
        exportPackage: @escaping () -> Void
    ) {
        self.canSave = canSave
        self.saveHandler = save
        self.saveAsHandler = saveAs
        self.canNew = canNew
        self.newSetlistHandler = newSetlist
        self.canOpen = canOpen
        self.openHandler = open
        self.canExportPackage = canExportPackage
        self.exportPackageHandler = exportPackage
    }

    func reset() {
        canSave = false
        canNew = false
        canOpen = false
        canExportPackage = false
        saveHandler = {}
        saveAsHandler = {}
        newSetlistHandler = {}
        openHandler = {}
        exportPackageHandler = {}
    }

    func save() { saveHandler() }
    func saveAs() { saveAsHandler() }
    func newSetlist() { newSetlistHandler() }
    func open() { openHandler() }
    func exportPackage() { exportPackageHandler() }
}
#endif
