import SwiftUI

extension AppColors {
    /// Colors for the live stage: setlist section cards, lane labels, and MIDI lanes.
    enum Live {
        static let sectionCardBorder = Color.white.opacity(0.06)
        static let sectionCardBorderActive = Color.white.opacity(0.14)
        /// Elapsed portion of the current section card.
        static let sectionProgress = AppColors.accent.opacity(0.55)

        /// Tags over the waveform and MIDI lanes: section names and device names.
        static let tagBackground = AppColors.surfaceElevated.opacity(0.92)

        static let midiLaneBackground = Color.white.opacity(0.06)
        static let midiEventDot = Color.white.opacity(0.85)
    }
}
