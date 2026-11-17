import SwiftUI

/// The app's color tokens. Fixed colors live in `Assets.xcassets` and are read through the
/// generated, compile-checked `ColorResource` symbols; tokens here may only compose those (or system
/// colors) with opacity. Views use these tokens instead of literal colors.
enum AppColors {
    /// Window/content background. macOS uses the system window background because the
    /// toolbar and sidebar materials are tuned to blend with it; a custom near-black makes
    /// the header read as a lighter bar, most visibly in full screen.
    static let backgroundPrimary: Color = {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.backgroundPrimary)
        #endif
    }()
    static let backgroundSecondary = Color(.backgroundSecondary)
    /// Setlist section header band. A translucent white lift rather than a fixed gray so it stays
    /// lighter than the content background on macOS, where that background is a system color.
    static let headerBand = Color.white.opacity(0.05)
    static let surface = Color(.surface)
    static let surfaceElevated = Color(.surfaceElevated)

    /// Dims content behind a modal overlay or progress card.
    static let scrim = Color.black.opacity(0.35)
    /// Lighter scrim behind a floating card that should keep the stage readable.
    static let scrimLight = Color.black.opacity(0.12)

    static let textPrimary = Color(.textPrimary)
    static let textSecondary = Color(.textSecondary)
    static let textTertiary = Color(.textTertiary)
    /// Row title while the row is highlighted but not selected.
    static let textHighlighted = textPrimary.opacity(0.8)
    /// Text and glyphs drawn on a saturated fill: an error banner, a track color, the accent.
    static let textOnFill = Color.white

    /// Brand orange (#E25303) — reserved for current/active state.
    static let accent = Color.accentColor
    /// Status pill filled with the accent, such as "Remote control connected".
    static let accentFill = accent.opacity(0.85)
    /// Error messages and failed operations.
    static let error = Color.red
    /// Background of a full-width error banner, such as a lost audio device.
    static let errorFill = error.opacity(0.85)
    /// Warnings: missing media, sections without a voice, a remote session that failed to start.
    static let warning = Color.orange
    /// Secondary row actions (such as swipe-to-edit) that need a tint distinct from `accent`.
    static let info = Color.blue

    static let separator = Color(.appSeparator)
    /// Dark hairline between side-by-side panes, matching the split-view column edge AppKit
    /// draws beside the sidebar. `separator` is a light lift that disappears against panes.
    static let paneDivider = Color.black.opacity(0.5)
    /// Hairline that lifts a dark card or pill off the background.
    static let cardBorder = Color.white.opacity(0.08)

    /// Color swatch outlines in the track group editor.
    static let swatchBorder = separator.opacity(0.5)
    static let swatchPreviewBorder = Color.secondary.opacity(0.4)

    /// Highlight over a control while input mapping is open, and while it waits for input.
    static let mappingHighlight = accent.opacity(0.25)
    static let mappingHighlightPending = accent.opacity(0.5)
    /// Pill showing a control's assigned MIDI or key shortcut.
    static let mappingBadgeBackground = Color.black.opacity(0.82)
    static let mappingBadgeBorder = Color.white.opacity(0.18)

    /// Recessed backdrop behind the shared transport buttons.
    static let transportStripBackground = Color.black.opacity(0.30)
    static let transportStripBorder = Color.white.opacity(0.055)

    /// Unfilled track of a playback scrubber.
    static let scrubberTrack = textPrimary.opacity(0.15)
    /// Elapsed part of a playback scrubber at rest. It brightens to `textPrimary` while dragged.
    static let scrubberFill = textPrimary.opacity(0.55)

    /// Resting glyph color for bare icon buttons.
    static let iconNeutral = Color(.iconNeutral)

    /// Transport glyph tints while play, loop, or fade is on.
    static let transportPlay = Color.green
    static let transportLoop = Color.purple
    static let transportFade = Color.red

    static let soloActive = Color(.soloActive)
    static let muteActive = Color(.muteActive)

    /// Highlighted track header background when the track row is selected.
    static let trackHeaderSelected = Color(.trackHeaderSelected)

    /// Editor section-marker blocks: the track palette's dark gray, lifting to its white when selected.
    static let sectionMarker = Color(.trackPaletteDarkGray)
    static let sectionMarkerSelected = Color(.trackPaletteWhite)
}
