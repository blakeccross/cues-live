import SwiftUI

/// The app's color roles. Each names what a color is for and picks it from `AppPalette`, so
/// restyling the app means repointing roles here rather than editing views. A few one-off hues
/// with a single purpose (meters, solo/mute, the playhead) come straight from `Assets.xcassets`.
/// Views use these roles instead of literal colors.
enum AppColors {
    /// Window/content background. macOS uses the system window background because the
    /// toolbar and sidebar materials are tuned to blend with it; a custom near-black makes
    /// the header read as a lighter bar, most visibly in full screen.
    static let backgroundPrimary: Color = {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        AppPalette.gray950
        #endif
    }()
    static let backgroundSecondary = AppPalette.gray900
    /// Setlist section header band. A translucent lift rather than a fixed gray so it stays
    /// lighter than the content background on macOS, where that background is a system color.
    static let headerBand = AppPalette.lift1
    static let surface = AppPalette.gray850
    static let surfaceElevated = AppPalette.gray800

    /// Dims content behind a modal overlay or progress card.
    static let scrim = AppPalette.shade4
    /// Lighter scrim behind a floating card that should keep the stage readable.
    static let scrimLight = AppPalette.shade2

    static let textPrimary = AppPalette.white
    static let textSecondary = AppPalette.gray300
    static let textTertiary = AppPalette.gray500
    /// Row title while the row is highlighted but not selected.
    static let textHighlighted = AppPalette.lift7
    /// Text and glyphs drawn on a saturated fill: an error banner, a track color, the accent.
    static let textOnFill = AppPalette.white

    /// Brand blue, reserved for current/active state.
    static let accent = AppPalette.accent
    /// Status pill filled with the accent, such as "Remote control connected".
    static let accentFill = AppPalette.accentStrong
    /// Error messages and failed operations.
    static let error = AppPalette.red
    /// Background of a full-width error banner, such as a lost audio device.
    static let errorFill = error.opacity(0.85)
    /// Warnings: missing media, sections without a voice, a remote session that failed to start.
    static let warning = AppPalette.orange
    /// Secondary row actions (such as swipe-to-edit) that need a tint distinct from `accent`.
    static let info = AppPalette.blue

    static let separator = AppPalette.lift3
    /// Dark hairline between side-by-side panes, matching the split-view column edge AppKit
    /// draws beside the sidebar. `separator` is a light lift that disappears against panes.
    static let paneDivider = AppPalette.shade5
    /// Hairline that lifts a dark card or pill off the background.
    static let cardBorder = AppPalette.lift2

    /// Color swatch outlines in the track group editor.
    static let swatchBorder = AppPalette.lift1
    static let swatchPreviewBorder = Color.secondary.opacity(0.4)

    /// Highlight over a control while input mapping is open, and while it waits for input.
    static let mappingHighlight = AppPalette.accentSoft
    static let mappingHighlightPending = AppPalette.accentMedium
    /// Pill showing a control's assigned MIDI or key shortcut.
    static let mappingBadgeBackground = AppPalette.shade6
    static let mappingBadgeBorder = AppPalette.lift4

    /// Recessed backdrop behind the shared transport buttons.
    static let transportStripBackground = AppPalette.shade4
    static let transportStripBorder = AppPalette.lift1

    /// Unfilled track of a playback scrubber.
    static let scrubberTrack = AppPalette.lift4
    /// Elapsed part of a playback scrubber at rest. It brightens to `textPrimary` while dragged.
    static let scrubberFill = AppPalette.lift5

    /// Resting glyph color for bare icon buttons.
    static let iconNeutral = AppPalette.gray300

    /// Transport glyph tints while play, loop, or fade is on.
    static let transportPlay = AppPalette.green
    static let transportLoop = AppPalette.purple
    static let transportFade = AppPalette.red

    static let soloActive = Color(.soloActive)
    static let muteActive = Color(.muteActive)

    /// Highlighted track header background when the track row is selected.
    static let trackHeaderSelected = AppPalette.gray750

    /// Selected setlist row: a light neutral lift, so it never competes with the accent marking
    /// the current song.
    static let rowSelection = AppPalette.lift3

    /// Editor section-marker blocks: the track palette's dark gray, lifting to its white when selected.
    static let sectionMarker = Color(.trackPaletteDarkGray)
    static let sectionMarkerSelected = Color(.trackPaletteWhite)
}
