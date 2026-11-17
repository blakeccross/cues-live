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
        static let laneDivider = Color(.timelineLaneDivider)

        /// Ruler baseline, and the ticks drawn when the ruler sits above empty space.
        static let measureGridLine = AppColors.separator.opacity(0.6)
        static let rulerBarTick = measureGridLine.opacity(0.75)
        static let rulerBeatTick = measureGridLine.opacity(0.4)
        /// Minor and major ticks on the seconds ruler.
        static let timeRulerTick = Color.secondary.opacity(0.5)
        /// Dot marking where a tempo or time signature change starts.
        static let rulerChangeMarker = Color(.timelineRulerMarker)

        /// Lane ticks drawn through the tracks. One black, heavier for bars than beats than eighths.
        static let barTick = Color.black.opacity(0.20)
        static let beatTick = Color.black.opacity(0.12)
        static let subdivisionTick = Color.black.opacity(0.08)

        /// Section-marker tick, drawn over the tracks.
        static let sectionMarkerLine = Color(.timelineSectionMarkerLine)

        /// In and out flags on the time ruler.
        static let playRangeFlag = Color(.timelinePlayRangeFlag)
        /// Wash over the timeline before the in point and after the out point.
        static let outsidePlayRange = Color(.timelinePlayRangeOutside)
        /// Shadow the played stretch casts past the out point, so it reads as raised.
        static let playRangeEdgeShadow = Color(.timelinePlayRangeEdgeShadow)

        /// Edit-selection wash composited over the lanes.
        static let selection = Color(.timelineSelection)

        /// Playback playhead line.
        static let playhead = Color(.timelinePlayhead)
        /// Insertion cursor shown while stopped.
        static let insertionCursor = Color(.timelineInsertionCursor)
        static let playheadHandleFill = Color(.timelinePlayheadHandleFill)
        static let playheadHandleBorder = Color(.timelinePlayheadHandleBorder)

        /// Track name on a clip header; dark on the light selected header, like Logic.
        static let clipHeaderText = Color.white.opacity(0.65)
        static let clipHeaderTextSelected = Color.black.opacity(0.72)
        /// Clip gain line across the clip body, and its dB readout.
        static let clipGainLine = Color.white.opacity(170.0 / 255.0)
        static let clipGainReadout = Color.white.opacity(200.0 / 255.0)
        static let fadeKnobFill = AppColors.scrim
        static let fadeKnobBorder = Color.white.opacity(0.78)
        static let fadeKnobBorderLit = Color.white.opacity(0.9)
    }
}
