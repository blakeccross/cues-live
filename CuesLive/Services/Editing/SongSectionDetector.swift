import AVFoundation
import Foundation
#if canImport(MusicUnderstanding)
import MusicUnderstanding
#endif

enum SongSectionDetectorError: LocalizedError {
    case unavailable
    case noAudio
    case mixFailed
    case noSectionsFound

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Section detection needs macOS 27 or iPadOS 27."
        case .noAudio:
            return "Add audio tracks before detecting sections."
        case .mixFailed:
            return "Couldn't prepare the song audio for analysis."
        case .noSectionsFound:
            return "No sections were found in this song."
        }
    }
}

/// Finds section boundaries with Apple's Music Understanding framework.
///
/// The framework returns time ranges without labels, so detected sections are
/// named "Section N" and left for the user to rename.
enum SongSectionDetector {
    static var isAvailable: Bool {
        #if canImport(MusicUnderstanding)
        if #available(macOS 27, iOS 27, *) { return true }
        #endif
        return false
    }

    /// Tracks that describe the song rather than belong to it; analyzing them would skew the result.
    static func analysisTracks(in song: Song) -> [AudioTrack] {
        song.sortedTracks.filter { track in
            let isClick = track.displayName.caseInsensitiveCompare(ClickTrackFileGenerator.trackDisplayName) == .orderedSame
            let isGuide = track.displayName.caseInsensitiveCompare(TrackGroupStore.guideGroupName) == .orderedSame
            return !isClick && !isGuide
        }
    }

    /// Section start times in seconds from the start of the song's audio files.
    static func detectSectionStarts(from urls: [URL]) async throws -> [TimeInterval] {
        #if canImport(MusicUnderstanding)
        guard #available(macOS 27, iOS 27, *) else { throw SongSectionDetectorError.unavailable }
        guard !urls.isEmpty else { throw SongSectionDetectorError.noAudio }

        let mix = try await mixedAsset(from: urls)
        defer { if let cleanupURL = mix.cleanupURL { try? FileManager.default.removeItem(at: cleanupURL) } }

        let session = try await MusicUnderstandingSession(asset: mix.asset)
        let result = try await session.analyze(for: [.structure])
        let ranges = result.structure?.sections ?? []
        return ranges.map { $0.start.seconds }.filter { $0.isFinite }
        #else
        throw SongSectionDetectorError.unavailable
        #endif
    }

    /// Turns detected starts into markers: sorted, de-duplicated, with the first section pinned to 0
    /// so the opening of the song always belongs to a section.
    static func markers(
        fromSectionStarts starts: [TimeInterval],
        songDuration: TimeInterval,
        minimumSectionDuration: TimeInterval = 1
    ) -> [ArrangementMarker] {
        let limit = songDuration > 0 ? songDuration : .greatestFiniteMagnitude
        var kept: [TimeInterval] = [0]
        for start in starts.sorted() where start > 0 && start < limit {
            if start - kept[kept.count - 1] < minimumSectionDuration { continue }
            kept.append(start)
        }
        // A short tail would become a section of its own; fold it into the previous one.
        if kept.count > 1, songDuration > 0, songDuration - kept[kept.count - 1] < minimumSectionDuration {
            kept.removeLast()
        }
        return kept.enumerated().map { index, start in
            ArrangementMarker(name: "Section \(index + 1)", startSeconds: start, sortOrder: index)
        }
    }

    // MARK: - Private

    private struct MixedAsset {
        let asset: AVURLAsset
        let cleanupURL: URL?
    }

    /// One track is analyzed in place; several are summed into a temporary file so the analysis hears the full mix.
    private static func mixedAsset(from urls: [URL]) async throws -> MixedAsset {
        let options = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        if urls.count == 1 {
            return MixedAsset(asset: AVURLAsset(url: urls[0], options: options), cleanupURL: nil)
        }

        let composition = AVMutableComposition()
        for url in urls {
            let source = AVURLAsset(url: url)
            guard let sourceTrack = try await source.loadTracks(withMediaType: .audio).first,
                  let compositionTrack = composition.addMutableTrack(
                      withMediaType: .audio,
                      preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { continue }
            let duration = try await source.load(.duration)
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: .zero
            )
        }
        guard !composition.tracks(withMediaType: .audio).isEmpty,
              let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw SongSectionDetectorError.mixFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cues-section-analysis-\(UUID().uuidString).m4a")
        do {
            try await export.export(to: outputURL, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw SongSectionDetectorError.mixFailed
        }
        return MixedAsset(asset: AVURLAsset(url: outputURL, options: options), cleanupURL: outputURL)
    }
}
