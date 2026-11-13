import SwiftUI

/// Zoom In and Zoom Out for whichever timeline or waveform strip has focus.
struct TimelineZoomActions {
    var canZoomIn = false
    var canZoomOut = false
    var zoomIn: () -> Void = {}
    var zoomOut: () -> Void = {}
}

private struct TimelineZoomActionsKey: FocusedValueKey {
    typealias Value = TimelineZoomActions
    static var defaultValue: Value? { nil }
}

extension FocusedValues {
    var timelineZoomActions: TimelineZoomActions? {
        get { self[TimelineZoomActionsKey.self] }
        set { self[TimelineZoomActionsKey.self] = newValue }
    }
}

#if os(macOS)
struct TimelineZoomCommands: Commands {
    @FocusedValue(\.timelineZoomActions) private var actions

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Zoom In") {
                actions?.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(actions?.canZoomIn != true)

            Button("Zoom Out") {
                actions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(actions?.canZoomOut != true)

            Divider()
        }
    }
}
#endif
