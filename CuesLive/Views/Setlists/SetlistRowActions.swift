import Foundation

/// What a row can do. Optional closures are hidden from the menu, swipe actions and
/// context menu when nil, so the remote list can offer a smaller set than the local one.
/// Removal is list-wide (`SetlistListView.onRemove`), so it can act on a multi-row selection.
struct SetlistRowActions {
    /// Loads the song stopped at its start, even mid-song, so the next song never starts by accident.
    var cue: (() -> Void)?
    var edit: (() -> Void)?
    var relink: (() -> Void)?
    var transitions: [SetlistTransition] = []
    var setTransition: ((SetlistTransition) -> Void)?
}
