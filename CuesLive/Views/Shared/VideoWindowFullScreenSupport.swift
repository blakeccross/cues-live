#if os(macOS)
import AppKit
import SwiftUI

/// Lets the window holding this view go full screen from the green button and the View menu, and
/// toggles full screen on a double-click in that window, so the Video window can fill a projector.
private struct VideoWindowFullScreenSupport: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowObservingView {
        WindowObservingView()
    }

    func updateNSView(_ view: WindowObservingView, context: Context) {}

    final class WindowObservingView: NSView {
        private var doubleClickMonitor: Any?
        private var behaviorObservation: NSKeyValueObservation?
        private var updateObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            Self.allowFullScreen(in: window)
            // SwiftUI configures a `Window` scene's window as an auxiliary full-screen window some
            // time after its content is attached, and again later, so put full screen back whenever
            // the behavior changes or the window updates.
            behaviorObservation = window.observe(\.collectionBehavior) { window, _ in
                MainActor.assumeIsolated { Self.allowFullScreen(in: window) }
            }
            updateObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: window,
                queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    Self.allowFullScreen(in: window)
                }
            }
            // A monitor rather than a gesture: only this window toggles, not whichever window is key.
            doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if event.clickCount == 2, let window = self?.window, event.window === window {
                    window.toggleFullScreen(nil)
                }
                return event
            }
        }

        private func stopObserving() {
            if let doubleClickMonitor {
                NSEvent.removeMonitor(doubleClickMonitor)
                self.doubleClickMonitor = nil
            }
            if let updateObserver {
                NotificationCenter.default.removeObserver(updateObserver)
                self.updateObserver = nil
            }
            behaviorObservation = nil
        }

        /// Only writes when something is off, so the observation does not feed itself.
        private static func allowFullScreen(in window: NSWindow) {
            let behavior = window.collectionBehavior
            if !behavior.contains(.fullScreenPrimary) || !behavior.isDisjoint(with: [.fullScreenNone, .fullScreenAuxiliary]) {
                window.collectionBehavior = behavior
                    .subtracting([.fullScreenNone, .fullScreenAuxiliary])
                    .union(.fullScreenPrimary)
            }
            if window.backgroundColor != .black {
                window.backgroundColor = .black
            }
        }

        /// Never takes clicks itself; it only watches the window.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension View {
    /// Makes the hosting window a full-screen window that a double-click toggles.
    func videoWindowFullScreen() -> some View {
        background(VideoWindowFullScreenSupport())
    }
}
#endif
