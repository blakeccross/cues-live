import SwiftUI

extension AppColors {
    /// Voice Memos–style colors for the live setlist waveform.
    enum LiveWaveform {
        static let played = Color(.liveWaveformPlayed)
        static let unplayed = Color(.liveWaveformUnplayed)
        static let background = Color(.liveWaveformBackground)
        /// Base for single-color waveforms; callers apply the played/unplayed opacities.
        static let monochrome = Color.white

        /// Playhead line drawn by the native scroll views.
        static let playhead = Color.white.opacity(0.92)
        static let playheadShadow = Color.black
        static let playheadShadowOpacity: Float = 0.35
    }
}
