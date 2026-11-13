import Foundation
import Observation

/// Connects the live setlist screen to the separate song editor window.
///
/// The setlist screen owns its `PlaybackCoordinator`; the editor window lives in another
/// scene and finds it here. The window edits whichever song the coordinator has active,
/// unless a song was sent to it with `edit(_:)`, and never takes over the audio engine.
@MainActor
@Observable
final class SetlistEditorLink {
    static let shared = SetlistEditorLink()

    /// The coordinator of the setlist screen on display, if any.
    private(set) var coordinator: PlaybackCoordinator?
    /// True while the setlist screen has pushed its own song editor, which owns the engine.
    private(set) var isInlineEditorOpen = false
    /// True while the editor window is on screen, so Edit opens songs there.
    private(set) var isWindowOpen = false
    /// A song the window shows instead of the active one. Cleared when the setlist reaches it.
    private(set) var pinnedSongID: UUID?

    /// The coordinator the editor window can follow. Nil while the inline editor owns the engine.
    var followableCoordinator: PlaybackCoordinator? {
        isInlineEditorOpen ? nil : coordinator
    }

    func attach(_ coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    /// Clears the link only when `coordinator` is still the attached one, so a stale
    /// screen disappearing after a new one appeared does not disconnect the window.
    /// The inline editor flag is left alone: pushing that editor hides the setlist screen.
    func detach(_ coordinator: PlaybackCoordinator) {
        guard self.coordinator === coordinator else { return }
        self.coordinator = nil
    }

    func setInlineEditorOpen(_ isOpen: Bool) {
        isInlineEditorOpen = isOpen
    }

    func setWindowOpen(_ isOpen: Bool) {
        isWindowOpen = isOpen
        if !isOpen {
            pinnedSongID = nil
        }
    }

    /// Shows `songID` in the window. The active song needs no pin; the window already follows it.
    func edit(_ songID: UUID) {
        pinnedSongID = songID == coordinator?.currentSong?.id ? nil : songID
    }

    /// Drops the pinned song so the window follows the setlist again.
    func followSetlist() {
        pinnedSongID = nil
    }

    /// Call when the setlist changes song. Reaching the pinned song resumes following from there.
    func activeSongDidChange(to songID: UUID?) {
        if songID == pinnedSongID {
            pinnedSongID = nil
        }
    }
}
