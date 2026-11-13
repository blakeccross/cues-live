import Foundation

/// Counts the copies of a screen on display. SwiftUI can show a new copy of a view before
/// it removes the old one (`NavigationSplitView` does this at launch), so their
/// `onAppear`/`onDisappear` calls overlap. Run setup on the first appearance and
/// teardown on the last disappearance, not on every call.
struct ScreenPresence {
    private(set) var visibleCount = 0

    /// Records an appearance. Returns true when it is the first copy on screen.
    mutating func appear() -> Bool {
        visibleCount += 1
        return visibleCount == 1
    }

    /// Records a disappearance. Returns true when no copy is left on screen.
    mutating func disappear() -> Bool {
        visibleCount = max(0, visibleCount - 1)
        return visibleCount == 0
    }
}
