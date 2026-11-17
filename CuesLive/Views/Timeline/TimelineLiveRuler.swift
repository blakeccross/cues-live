import SwiftUI

/// What the rulers above the lanes show, for the AppKit ruler that covers them during a live zoom
/// on macOS. Built by the editor from the same values its SwiftUI rulers read.
struct TimelineLiveRuler {
    let duration: TimeInterval
    let contentWidth: CGFloat
    let sections: [SongSection]
    let selectedSectionID: UUID?
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    let loopSectionIDs: Set<UUID>
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    /// The in and out points, resolved against the song's end.
    let playRange: ClosedRange<TimeInterval>

    #if os(macOS)
    func scene(in environment: EnvironmentValues) -> TimelineLiveRulerPainter.Scene {
        let resolve = { (color: Color) in color.resolve(in: environment).cgColor }
        let safeDuration = max(duration, 0.001)
        return TimelineLiveRulerPainter.Scene(
            duration: safeDuration,
            contentWidth: contentWidth,
            sections: sections.map { section in
                let isSelected = section.id == selectedSectionID
                var fill = isSelected ? AppColors.sectionMarkerSelected : AppColors.sectionMarker
                // A cued block pulses between its fill and a dimmer version of it.
                if section.id == cuedSectionID, !cueFlashPhase {
                    fill = fill.opacity(0.45)
                }
                return TimelineLiveRulerPainter.Section(
                    start: section.timelineStartSeconds,
                    end: section.timelineEndSeconds,
                    name: section.name,
                    loops: loopSectionIDs.contains(section.id),
                    fillColor: resolve(fill),
                    textColor: resolve(isSelected ? AppColors.backgroundSecondary : AppColors.textPrimary)
                )
            },
            meter: TimelineRulerSegment.segments(
                timeSignatureChanges: timeSignatureChanges,
                tempoChanges: tempoChanges,
                duration: safeDuration
            ).map { TimelineLiveRulerPainter.Value(start: $0.startTime, end: $0.endTime, text: $0.label) },
            tempo: TimelineRulerSegment.segments(
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                duration: safeDuration
            ).map { TimelineLiveRulerPainter.Value(start: $0.startTime, end: $0.endTime, text: $0.label) },
            playRange: playRange,
            backgroundColor: resolve(AppColors.Timeline.stickyRulerBackground),
            tickColor: resolve(AppColors.Timeline.timeRulerTick),
            valueColor: resolve(.secondary),
            dividerColor: resolve(AppColors.Timeline.divider),
            changeMarkerColor: resolve(AppColors.Timeline.rulerChangeMarker),
            flagColor: resolve(AppColors.Timeline.playRangeFlag),
            outsidePlayRangeColor: resolve(AppColors.Timeline.outsidePlayRange),
            playRangeEdgeShadowColor: resolve(AppColors.Timeline.playRangeEdgeShadow),
            blockBorderColor: resolve(AppColors.paneDivider)
        )
    }
    #endif
}
