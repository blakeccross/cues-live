import Foundation

/// Display data for one setlist row. Local (SwiftData) and remote (DTO) setlists both map into this,
/// so they share a single list implementation.
struct SetlistRowModel: Identifiable {
    struct Song {
        var title: String
        var durationText: String
        var keyText: String? = nil
        var bpmText: String? = nil
        /// Position among songs only (headers are not counted).
        var playbackIndex: Int
        var hasMissingMedia: Bool = false
        var hasSmartGuide: Bool = false
        /// Transition to the next song; nil for the last song.
        var transition: SetlistTransition? = nil
        /// Arrangement sections, listed when the row is expanded.
        var sections: [SongSection] = []
    }

    enum Kind {
        case header(title: String, timeText: String?)
        case song(Song)
    }

    let id: AnyHashable
    let kind: Kind
}
