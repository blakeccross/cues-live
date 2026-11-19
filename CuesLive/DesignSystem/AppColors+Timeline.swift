import SwiftUI

extension AppColors {
    /// Colors for the edit timeline: rulers, lanes, track headers, and the playhead.
    enum Timeline {
        static let background = AppColors.backgroundPrimary
        /// Fully opaque background for pinned ruler headers so scrolling tracks don't show through.
        static let stickyRulerBackground = AppColors.surfaceElevated
        static let trackHeaderBackground = AppColors.backgroundSecondary
        static let trackHeaderColumnBackground = AppColors.backgroundPrimary
        static let mixButtonBackground = AppColors.surface

        static let divider = AppColors.separator
        /// Hairline between edit-view track rows.
        static let laneDivider = AppPalette.gray700

        /// Minor and major ticks on the seconds ruler.
        static let timeRulerTick = Color.secondary.opacity(0.5)
        /// Dot marking where a tempo or time signature change starts.
        static let rulerChangeMarker = AppPalette.gray500

        /// Lane ticks drawn through the tracks. One black, heavier for bars than beats than eighths.
        static let barTick = AppPalette.shade3
        static let beatTick = AppPalette.shade2
        static let subdivisionTick = AppPalette.shade1

        /// Section-marker tick, drawn over the tracks.
        static let sectionMarkerLine = AppPalette.gray600

        /// In and out flags on the time ruler.
        static let playRangeFlag = AppPalette.gray400
        /// Wash over the timeline before the in point and after the out point.
        static let outsidePlayRange = AppPalette.shade4
        /// Shadow the played stretch casts past the out point, so it reads as raised.
        static let playRangeEdgeShadow = AppPalette.shade5

        /// Edit-selection wash composited over the lanes.
        static let selection = Color(.timelineSelection)

        /// Playback playhead line.
        static let playhead = Color(.timelinePlayhead)
        /// Insertion cursor shown while stopped.
        static let insertionCursor = AppPalette.gray200
        static let playheadHandleFill = AppPalette.gray200
        static let playheadHandleBorder = AppPalette.gray900

        /// Track name on a clip header; dark on the light selected header, like Logic.
        static let clipHeaderText = AppPalette.lift6
        static let clipHeaderTextSelected = AppPalette.shade6
        /// Clip gain line across the clip body, and its dB readout.
        static let clipGainLine = AppPalette.lift6
        static let clipGainReadout = AppPalette.lift7
        static let fadeKnobFill = AppColors.scrim
        static let fadeKnobBorder = AppPalette.lift7
        static let fadeKnobBorderLit = AppPalette.lift8
    }
}
