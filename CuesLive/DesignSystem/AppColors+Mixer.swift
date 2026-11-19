import SwiftUI

extension AppColors {
    /// Colors for the mixer: solo/mute buttons, faders, and level meters.
    enum Mixer {
        /// Solo/mute label while its button is lit.
        static let buttonActiveLabel = AppPalette.shade6

        static let meterLevel = Color(.meterLevel)
        /// Live level drawn behind the volume readout.
        static let readoutLevel = meterLevel.opacity(0.55)
        /// Live level beside a group fader.
        static let faderLevel = meterLevel.opacity(0.85)

        /// Grip lines on the fader thumb.
        static let faderGrip = AppColors.textTertiary.opacity(0.35)
        /// Center line on the fader thumb.
        static let faderThumbLine = AppPalette.lift8
        /// Fader scale ticks other than unity.
        static let scaleTick = AppColors.textTertiary.opacity(0.6)
    }
}
