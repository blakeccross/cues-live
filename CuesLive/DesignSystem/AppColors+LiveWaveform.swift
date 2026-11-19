import SwiftUI

extension AppColors {
    /// Voice Memos–style colors for the live setlist waveform.
    enum LiveWaveform {
        static let background = AppPalette.gray850
        /// Section markers in the ribbon above the waveform, in songs other than the current one.
        static let sectionMarker = AppPalette.gray750
        /// Ribbon the playhead has passed in the current song.
        static let sectionMarkerPlayed = AppColors.accent
        /// Ribbon still ahead of the playhead in the current song.
        static let sectionMarkerUnplayed = AppColors.accent.darkened(sRGBBy: 0.45)
        static let sectionLabel = AppColors.textOnFill

        /// Playhead line drawn by the native scroll views, the same red as the edit view's.
        static let playhead = AppColors.Timeline.playhead
    }
}
