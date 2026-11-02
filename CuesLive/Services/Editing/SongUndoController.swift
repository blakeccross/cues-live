import Foundation
import Observation

@Observable
final class SongUndoController: NSObject {
    private let undoManager = UndoManager()
    private(set) var isApplyingUndo = false
    /// Bumped whenever the undo stack changes so SwiftUI observes `canUndo` / `canRedo`.
    private var stackRevision = 0

    var canUndo: Bool {
        _ = stackRevision
        return undoManager.canUndo
    }

    var canRedo: Bool {
        _ = stackRevision
        return undoManager.canRedo
    }

    var undoActionName: String? {
        _ = stackRevision
        return undoManager.undoActionName
    }

    var redoActionName: String? {
        _ = stackRevision
        return undoManager.redoActionName
    }

    override init() {
        super.init()
        undoManager.levelsOfUndo = 50
    }

    func registerChange(
        actionName: String,
        before: SongEditSnapshot,
        after: SongEditSnapshot,
        apply: @escaping (SongEditSnapshot) -> Void
    ) {
        guard before != after else { return }
        guard !isApplyingUndo else { return }

        undoManager.registerUndo(withTarget: self) { target in
            target.applySnapshot(before, actionName: actionName, paired: after, using: apply)
        }
        undoManager.setActionName(actionName)
        refreshStackState()
    }

    func undo() {
        undoManager.undo()
        refreshStackState()
    }

    func redo() {
        undoManager.redo()
        refreshStackState()
    }

    private func refreshStackState() {
        stackRevision &+= 1
    }

    private func applySnapshot(
        _ snapshot: SongEditSnapshot,
        actionName: String,
        paired: SongEditSnapshot,
        using apply: @escaping (SongEditSnapshot) -> Void
    ) {
        isApplyingUndo = true
        apply(snapshot)
        isApplyingUndo = false

        undoManager.registerUndo(withTarget: self) { target in
            target.applySnapshot(paired, actionName: actionName, paired: snapshot, using: apply)
        }
        undoManager.setActionName(actionName)
        refreshStackState()
    }
}
