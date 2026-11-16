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
    /// Each track's clips, in `trackSources` order. Empty when unknown (remote sessions); the
    /// combined waveform then maps every file through `peakClips` instead.
    let trackClips: [[TrackClip]]
    let fileDuration: TimeInterval
    /// The song's in point. The lane starts here.
    let startTime: TimeInterval
    /// The song's out point, on its timeline. The lane ends here.
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
    /// Changes when any track file is rewritten in place, so a cached waveform is reloaded even
    /// though the paths and durations stayed the same. 0 when unknown (remote sessions).
    let audioRevision: Int

    var id: UUID { songID }

    var loopSectionIDs: Set<UUID> { sections.loopSectionIDs }

    /// The in-to-out stretch the lane shows.
    var window: LiveLaneWindow {
        LiveLaneWindow(start: startTime, end: timelineDuration)
    }

    var contentWidth: CGFloat {
        TimelineLayout.contentWidth(for: window.duration, zoom: 1)
    }

    init(
        songID: UUID,
        songName: String,
        trackSources: [(url: URL, duration: TimeInterval)],
        trackClips: [[TrackClip]] = [],
        fileDuration: TimeInterval,
        startTime: TimeInterval = 0,
        timelineDuration: TimeInterval,
        sections: [SongSection],
        peakClips: [TrackClip],
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        showsMeasureGrid: Bool,
        precomputedSourcePeaks: [Float]? = nil,
        midiLanes: [LiveMIDILaneSnapshot] = [],
        audioRevision: Int = 0
    ) {
        self.songID = songID
        self.songName = songName
        self.trackSources = trackSources
        self.trackClips = trackClips
        self.fileDuration = fileDuration
        self.startTime = startTime
        self.timelineDuration = timelineDuration
        self.sections = sections
        self.peakClips = peakClips
        self.tempoChanges = tempoChanges
        self.timeSignatureChanges = timeSignatureChanges
        self.showsMeasureGrid = showsMeasureGrid
        self.precomputedSourcePeaks = precomputedSourcePeaks
        self.midiLanes = midiLanes
        self.audioRevision = audioRevision
    }

    func withPrecomputedPeaks(_ peaks: [Float]?) -> LiveSongWaveformSnapshot {
        LiveSongWaveformSnapshot(
            songID: songID,
            songName: songName,
            trackSources: trackSources,
            trackClips: trackClips,
            fileDuration: fileDuration,
            startTime: startTime,
            timelineDuration: timelineDuration,
            sections: sections,
            peakClips: peakClips,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            showsMeasureGrid: showsMeasureGrid,
            precomputedSourcePeaks: peaks,
            midiLanes: midiLanes,
            audioRevision: audioRevision
        )
    }
}

enum LiveSetlistTimelineItem: Identifiable {
    /// `timeSeconds` is how long the header's segment of the show runs, when it has one.
    case header(scrollID: String, title: String, timeSeconds: TimeInterval? = nil)
    /// `overlapSeconds` is how far the next song starts before this one ends, when
    /// `transitionAfter` is an overlap and its length is known.
    case song(
        songID: UUID,
        playbackIndex: Int,
        transitionAfter: SetlistTransition?,
        overlapSeconds: TimeInterval? = nil
    )

    var id: String {
        switch self {
        case .header(let scrollID, _, _):
            scrollID
        case .song(_, let playbackIndex, _, _):
            "song-\(playbackIndex)"
        }
    }
}
