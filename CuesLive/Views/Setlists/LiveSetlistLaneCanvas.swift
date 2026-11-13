import SwiftUI

/// The song lanes as the setlist lane canvas draws them, before colors are resolved.
///
/// The canvas is as wide as the viewport and does not scroll; the setlist scroll view owns it
/// and redraws it on each display-link frame. Lane positions come from the scroll model.
struct LiveSetlistLaneCanvas: Equatable {
    struct Song: Equatable {
        /// Setlist position, matching the scroll model's lanes.
        let index: Int
        let source: LiveSetlistWaveformSource
        let duration: TimeInterval
        let sections: [SongSection]
        let tempoChanges: [TempoChange]
        let timeSignatureChanges: [TimeSignatureChange]
        let showsMeasureGrid: Bool
        let isCurrent: Bool

        init(index: Int, snapshot: LiveSongWaveformSnapshot, isCurrent: Bool) {
            self.index = index
            source = LiveSetlistWaveformSource(snapshot)
            duration = max(snapshot.timelineDuration, 0.001)
            sections = snapshot.sections
            tempoChanges = snapshot.tempoChanges
            timeSignatureChanges = snapshot.timeSignatureChanges
            showsMeasureGrid = snapshot.showsMeasureGrid
            self.isCurrent = isCurrent
        }
    }

    var songs: [Song] = []
    /// Cued section of the current song.
    var cuedSectionID: UUID?
    var cueFlashPhase = false

    func scene(in environment: EnvironmentValues) -> LiveSetlistLanePainter.Scene {
        func resolved(_ color: Color) -> CGColor {
            color.resolve(in: environment).cgColor
        }
        return LiveSetlistLanePainter.Scene(
            songs: songs.map { song in
                LiveSetlistLanePainter.Song(
                    index: song.index,
                    source: song.source,
                    duration: song.duration,
                    bands: song.sections.enumerated().map { index, section in
                        let background = ArrangementSectionPalette.colors(for: index).background
                        return LiveSetlistLanePainter.Band(
                            start: section.timelineStartSeconds,
                            end: section.timelineEndSeconds,
                            color: resolved(background.opacity(ArrangementSectionPalette.backgroundFillOpacity)),
                            cuedColor: resolved(background.opacity(ArrangementSectionPalette.backgroundCueFillOpacity)),
                            isCued: song.isCurrent && section.id == cuedSectionID
                        )
                    },
                    tempoChanges: song.tempoChanges,
                    timeSignatureChanges: song.timeSignatureChanges,
                    showsMeasureGrid: song.showsMeasureGrid,
                    isCurrent: song.isCurrent
                )
            },
            cueFlashPhase: cueFlashPhase,
            backgroundColor: resolved(.liveVoiceMemosBackground),
            separatorColor: resolved(AppColors.separator),
            accentColor: resolved(AppColors.accent)
        )
    }
}
