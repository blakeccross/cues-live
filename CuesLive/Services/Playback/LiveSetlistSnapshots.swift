import CoreGraphics
import Foundation

/// One MIDI device's cue points for the setlist view's read-only MIDI lane.
struct LiveMIDILaneSnapshot: Identifiable, Equatable {
    let id: UUID
    let deviceName: String
    let events: [MIDIEvent]
}

struct LiveSongWaveformSnapshot: Identifiable {
    let songID: UUID
    let songName: String
    let trackSources: [(url: URL, duration: TimeInterval)]
    let fileDuration: TimeInterval
    let timelineDuration: TimeInterval
    /// Sections used for labels, cueing, and loop badges.
    let sections: [SongSection]
    /// Clips used to map timeline time to source audio for the combined waveform.
    let peakClips: [TrackClip]
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    /// When false, the setlist lane hides measure ticks (`song.bpm` is unset).
    let showsMeasureGrid: Bool
    /// When set (e.g. remote session or local setlist peak warm), peaks are used
    /// directly and track files are not decoded on the setlist render path.
    let precomputedSourcePeaks: [Float]?
    /// One lane per MIDI device on this song, for the setlist's read-only MIDI strip.
    let midiLanes: [LiveMIDILaneSnapshot]

    var id: UUID { songID }

    var loopSectionIDs: Set<UUID> { sections.loopSectionIDs }

    var contentWidth: CGFloat {
        TimelineLayout.contentWidth(for: timelineDuration, zoom: 1)
    }

    init(
        songID: UUID,
        songName: String,
        trackSources: [(url: URL, duration: TimeInterval)],
        fileDuration: TimeInterval,
        timelineDuration: TimeInterval,
        sections: [SongSection],
        peakClips: [TrackClip],
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        showsMeasureGrid: Bool,
        precomputedSourcePeaks: [Float]? = nil,
        midiLanes: [LiveMIDILaneSnapshot] = []
    ) {
        self.songID = songID
        self.songName = songName
        self.trackSources = trackSources
        self.fileDuration = fileDuration
        self.timelineDuration = timelineDuration
        self.sections = sections
        self.peakClips = peakClips
        self.tempoChanges = tempoChanges
        self.timeSignatureChanges = timeSignatureChanges
        self.showsMeasureGrid = showsMeasureGrid
        self.precomputedSourcePeaks = precomputedSourcePeaks
        self.midiLanes = midiLanes
    }

    func withPrecomputedPeaks(_ peaks: [Float]?) -> LiveSongWaveformSnapshot {
        LiveSongWaveformSnapshot(
            songID: songID,
            songName: songName,
            trackSources: trackSources,
            fileDuration: fileDuration,
            timelineDuration: timelineDuration,
            sections: sections,
            peakClips: peakClips,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            showsMeasureGrid: showsMeasureGrid,
            precomputedSourcePeaks: peaks,
            midiLanes: midiLanes
        )
    }
}

enum LiveSetlistTimelineItem: Identifiable {
    case header(scrollID: String, title: String)
    case song(songID: UUID, playbackIndex: Int, transitionAfter: SetlistTransition?)

    var id: String {
        switch self {
        case .header(let scrollID, _):
            scrollID
        case .song(_, let playbackIndex, _):
            "song-\(playbackIndex)"
        }
    }
}
