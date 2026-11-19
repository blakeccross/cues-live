import SwiftUI

#if os(macOS)
import AppKit

extension View {
    /// Turns off the native selection highlight of the `List` containing this row, so the row
    /// can draw its own through `listRowBackground`. Selection itself keeps working.
    func listSelectionHighlightHidden() -> some View {
        background(ListSelectionHighlightRemover())
    }
}

/// Finds the table view that backs a SwiftUI `List` and stops it drawing selected rows.
private struct ListSelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> RemoverView {
        RemoverView()
    }

    func updateNSView(_ nsView: RemoverView, context: Context) {}

    final class RemoverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var ancestor = superview
            while let view = ancestor, !(view is NSTableView) {
                ancestor = view.superview
            }
            if let tableView = ancestor as? NSTableView, tableView.selectionHighlightStyle != .none {
                tableView.selectionHighlightStyle = .none
            }
        }
    }
}
#endif
