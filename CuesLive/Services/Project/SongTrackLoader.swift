import Foundation

enum SongTrackLoader {
    typealias TrackInput = (
        id: UUID,
        url: URL,
        relativePath: String,
        settings: AudioEngineManager.TrackSettings,
        groupID: UUID?
    )

    static func trackInputs(for song: Song) throws -> [TrackInput] {
        try song.sortedTracks.compactMap { track in
            guard let url = try playbackURL(for: song, track: track) else { return nil }
            return (
                id: track.id,
                url: url,
                relativePath: track.mediaPath ?? track.relativeFilePath,
                settings: AudioEngineManager.TrackSettings(track: track),
                groupID: track.group?.id
            )
        }
    }

    /// The track's own media. Key and tempo changes are applied live, so nothing is baked.
    static func playbackURL(for song: Song, track: AudioTrack) throws -> URL? {
        FileStore.trackURL(for: song, track: track)
    }

    /// Live and setlist playback payloads. Missing files are skipped. When none are
    /// left, load an empty song so the timeline, cues, and MIDI still run.
    static func playbackPayloads(
        for song: Song
    ) throws -> [AudioEngineManager.PreparedTrackPayload] {
        let trackInputs = try trackInputs(for: song)
        if trackInputs.isEmpty, !song.sortedTracks.isEmpty {
            return []
        }
        return try streamingPayloads(trackInputs: trackInputs)
    }

    /// Builds payloads that stream their audio from disk on demand instead of
    /// decoding the entire stem into memory. This is cheap (it only opens each
    /// file and reads its header), so songs become near-instant to load.
    static func streamingPayloads(
        trackInputs: [TrackInput]
    ) throws -> [AudioEngineManager.PreparedTrackPayload] {
        guard !trackInputs.isEmpty else {
            throw PlaybackCoordinatorError.noTracks
        }

        return try trackInputs.enumerated().map { _, input in
            let buffer = try StreamingStemBuffer(url: input.url)
            var settings = input.settings
            if settings.trimEnd == nil {
                settings.trimEnd = Double(buffer.frameCount) / buffer.sampleRate
            }
            return AudioEngineManager.PreparedTrackPayload(
                id: input.id,
                buffer: buffer,
                settings: settings,
                groupID: input.groupID
            )
        }
    }

    static func timelineDuration(for song: Song) -> TimeInterval {
        SongProjectBridge.projectStateOrDefaults(for: song).timeline.duration
    }
}
