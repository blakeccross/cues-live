import SwiftUI

extension AppColors {
    /// Colors for the live stage: setlist section cards, lane labels, and MIDI lanes.
    enum Live {
        static let sectionCardBorder = AppPalette.lift1
        static let sectionCardBorderActive = AppPalette.lift4
        /// Elapsed portion of the current section card.
        static let sectionProgress = AppPalette.accentMedium

        /// Tags over the waveform and MIDI lanes: section names and device names.
        static let tagBackground = AppColors.surfaceElevated.opacity(0.92)

        static let midiLaneBackground = AppPalette.lift1
        static let midiEventDot = AppPalette.lift8

        /// Block for a continue between songs in the setlist strip.
        static let transitionContinueRibbon = Color(.liveTransitionContinue)
        /// Block for a stop between songs in the setlist strip.
        static let transitionStopRibbon = Color(.liveTransitionStop)
        /// Shade along a transition block's edges where it meets a song.
        static let transitionEdgeShadow = AppPalette.shade4
    }
}
