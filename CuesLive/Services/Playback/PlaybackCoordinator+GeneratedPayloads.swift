import Foundation

/// Audio the setlist plays beside a song's stems without it being a track: timecode and the click.
extension PlaybackCoordinator {
    func appendGeneratedPayloads(
        to payloads: inout [AudioEngineManager.PreparedTrackPayload],
        song: Song,
        songIndex: Int
    ) throws {
        let duration = timelineDuration(for: song)
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        ClickPlaybackSupport.appendPayload(
            to: &payloads,
            for: song,
            tempoChanges: projectState.tempoChanges,
            timeSignatureChanges: projectState.timeSignatureChanges,
            duration: duration
        )

        let settings = timecodeSettingsProvider?() ?? .default
        guard settings.isEnabled else { return }

        try TimecodePlaybackSupport.appendPayloadIfNeeded(
            to: &payloads,
            settings: settings,
            songIndex: songIndex,
            priorSongDurations: priorSongDurations(upTo: songIndex),
            duration: duration,
            groupID: timecodeGroupIDProvider?()
        )
    }

    private func priorSongDurations(upTo songIndex: Int) -> [TimeInterval] {
        guard songIndex > 0 else { return [] }
        return songs.prefix(songIndex).map(timelineDuration(for:))
    }

    private func timelineDuration(for song: Song) -> TimeInterval {
        waveformSnapshotsBySongID[song.id]?.timelineDuration
            ?? TimecodePlaybackSupport.timelineDuration(for: song)
    }
}
