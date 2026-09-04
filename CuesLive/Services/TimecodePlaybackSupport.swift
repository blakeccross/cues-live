import Foundation
import SwiftData

enum TimecodePlaybackSupport {
    static let groupName = "Timecode"
    static let payloadID = UUID(uuidString: "00000000-0000-4000-8000-00000000A001")!

    static func makePayload(
        settings: TimecodeSettingsSnapshot,
        songIndex: Int,
        priorSongDurations: [TimeInterval],
        duration: TimeInterval,
        groupID: UUID?
    ) throws -> AudioEngineManager.PreparedTrackPayload? {
        guard settings.isEnabled, duration > 0 else { return nil }

        let start = TimecodeStartCalculator.startTimecode(
            settings: settings,
            songIndex: songIndex,
            priorSongDurations: priorSongDurations
        )
        let buffer = try ProceduralLTCBuffer(
            duration: duration,
            start: start,
            frameRate: settings.frameRate
        )

        let trackSettings = AudioEngineManager.TrackSettings(
            volume: 1,
            isMuted: false,
            isSolo: false,
            trimStart: 0,
            trimEnd: duration,
            pitchCents: 0,
            excludeFromTranspose: true,
            ignoresSolo: true,
            bypassesArrangementMapping: true
        )

        return AudioEngineManager.PreparedTrackPayload(
            id: payloadID,
            buffer: buffer,
            settings: trackSettings,
            groupID: groupID
        )
    }

    static func appendPayloadIfNeeded(
        to payloads: inout [AudioEngineManager.PreparedTrackPayload],
        settings: TimecodeSettingsSnapshot,
        songIndex: Int,
        priorSongDurations: [TimeInterval],
        duration: TimeInterval,
        groupID: UUID?
    ) throws {
        guard let payload = try makePayload(
            settings: settings,
            songIndex: songIndex,
            priorSongDurations: priorSongDurations,
            duration: duration,
            groupID: groupID
        ) else {
            return
        }
        payloads.removeAll { $0.id == payloadID }
        payloads.append(payload)
    }

    static func resolveGroupID(in context: ModelContext) -> UUID? {
        TrackGroupStore.ensureDefaults(in: context)
        return TrackGroupStore.findOrCreateGroup(named: groupName, in: context)?.id
    }

    static func isTimecodeGroup(_ group: TrackGroup) -> Bool {
        group.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(groupName) == .orderedSame
    }

    static func timelineDuration(for song: Song) -> TimeInterval {
        SongTrackLoader.timelineDuration(for: song) { trackID in
            guard let track = song.sortedTracks.first(where: { $0.id == trackID }),
                  let url = FileStore.trackURL(for: song, track: track) else {
                return 1
            }
            return FileStore.fileDuration(at: url) ?? 1
        }
    }
}
