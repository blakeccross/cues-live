import SwiftUI

extension AppColors {
    /// Voice Memos–style colors for the live setlist waveform.
    enum LiveWaveform {
        static let played = Color(.liveWaveformPlayed)
        static let unplayed = Color(.liveWaveformUnplayed)
        static let background = Color(.liveWaveformBackground)
        /// Section markers in the ribbon above the waveform, in songs other than the current one.
        static let sectionMarker = Color(.liveWaveformSectionMarker)
        /// Ribbon the playhead has passed in the current song.
        static let sectionMarkerPlayed = AppColors.accent
        /// Ribbon still ahead of the playhead in the current song.
        static let sectionMarkerUnplayed = AppColors.accent.darkened(sRGBBy: 0.45)
        static let sectionLabel = AppColors.textOnFill
        /// Base for single-color waveforms; callers apply the played/unplayed opacities.
        static let monochrome = Color.white

        /// Playhead line drawn by the native scroll views.
        static let playhead = Color(.liveWaveformPlayhead)
        static let playheadShadow = Color.black
        static let playheadShadowOpacity: Float = 0.35
    }
}
