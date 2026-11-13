import Foundation

/// Applies edits from the song editor window to the song the setlist is playing,
/// without reloading audio unless the song's media changed.
extension PlaybackCoordinator {
    /// True when the audible engine holds `songID` and is not between songs.
    func hasLoadedSong(_ songID: UUID) -> Bool {
        isLoaded && !isLoadingSong && loadedSongID == songID
    }

    func applyEditedArrangement(_ timeline: SongTimeline, songID: UUID) {
        guard hasLoadedSong(songID) else { return }
        let engine = playbackEngine
        let previousDuration = engine.duration
        engine.setArrangement(SongPlaybackLayout(timeline: timeline))
        guard engine.duration != previousDuration else { return }

        // The UI clock only mirrors the song's length; keep it matched to the audible engine.
        let clock = AudioEngineManager.shared
        if clock !== engine {
            clock.retargetTimeline(duration: engine.duration, at: clock.currentTime)
        }
        // The overlap into the next song starts relative to the end, which just moved.
        if incomingAudioEngine == nil {
            configureOverlapSchedulingIfNeeded()
        }
    }

    func applyEditedTempoMap(
        _ tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        songID: UUID
    ) {
        guard hasLoadedSong(songID) else { return }
        let engine = playbackEngine
        engine.setTempoMap(tempoChanges, timeSignatureChanges: timeSignatureChanges)
        let clock = AudioEngineManager.shared
        if clock !== engine {
            clock.setTempoMap(tempoChanges, timeSignatureChanges: timeSignatureChanges)
        }
    }

    /// Re-prepares the overlap into `songID` when it is next, so the prefetched layout
    /// picks up the edit. Does nothing once that overlap has started.
    func prepareIncomingSongAfterEdit(_ songID: UUID) {
        guard isLoaded, nextSong?.id == songID, incomingAudioEngine == nil else { return }
        configureOverlapSchedulingIfNeeded()
    }

    func applyEditedMIDI(_ events: [MIDIScheduler.ScheduledEvent], songID: UUID) {
        guard hasLoadedSong(songID) else { return }
        playbackEngine.configureMIDI(events: events)
    }

    /// Reloads the song's stems after tracks were added, removed or regenerated,
    /// resuming from the same position when it was playing.
    func reloadEditedSong(_ songID: UUID) {
        guard currentSong?.id == songID else { return }
        loadCurrentSong(autoPlay: isPlaying, preservedTime: currentTime)
    }
}
