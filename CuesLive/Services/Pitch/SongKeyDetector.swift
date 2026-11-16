import AVFoundation
import Foundation
#if canImport(MusicUnderstanding)
import MusicUnderstanding
#endif

/// Finds a song's key on device with Apple's Music Understanding framework (macOS 27, iOS 27).
/// The harmonic stems are layered into one composition so the analysis hears the whole arrangement.
enum SongKeyDetector {
    struct DetectedKey: Hashable, Sendable {
        let key: SongMusicalKey
        let mode: SongKeyMode

        var label: String { key.label(mode: mode) }
    }

    enum DetectionError: LocalizedError {
        case unsupportedSystem
        case noAudio
        case noKeyFound
        case protectedContent

        var errorDescription: String? {
            switch self {
            case .unsupportedSystem:
                return "Key detection requires macOS 27 or iPadOS 27."
            case .noAudio:
                return "No readable audio was found to analyze."
            case .noKeyFound:
                return "A clear key could not be detected."
            case .protectedContent:
                return "Protected audio cannot be analyzed."
            }
        }
    }

    /// Filename fragments of stems that carry no pitch information and would only blur the analysis.
    private static let nonHarmonicNamePrefixes = [
        "click", "metronome", "cue", "guide", "count", "timecode", "ltc", "smpte",
        "drum", "kick", "snare", "snr", "tom", "hat", "hihat", "overhead", "room", "trig",
        "perc", "cymbal", "crash", "ride", "shaker", "tamb", "clap", "conga", "bongo"
    ]

    static var isSupported: Bool {
        #if canImport(MusicUnderstanding)
        if #available(macOS 27.0, iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Detects the key that covers the largest share of the song.
    /// - Parameter folderURL: Security-scoped folder the stems live in; access is held for the analysis.
    static func detectKey(folderURL: URL, trackURLs: [URL]) async throws -> DetectedKey {
        #if canImport(MusicUnderstanding)
        if #available(macOS 27.0, iOS 27.0, *) {
            let didAccess = folderURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }
            return try await analyze(harmonicStems(in: trackURLs))
        }
        #endif
        throw DetectionError.unsupportedSystem
    }

    /// Stems worth analyzing, or every stem when name matching would leave nothing.
    static func harmonicStems(in trackURLs: [URL]) -> [URL] {
        let harmonic = trackURLs.filter { url in
            let tokens = url.deletingPathExtension().lastPathComponent
                .lowercased()
                .split { !$0.isLetter }
            return !tokens.contains { token in
                nonHarmonicNamePrefixes.contains { token.hasPrefix($0) }
            }
        }
        return harmonic.isEmpty ? trackURLs : harmonic
    }

    #if canImport(MusicUnderstanding)
    @available(macOS 27.0, iOS 27.0, *)
    private static func analyze(_ stemURLs: [URL]) async throws -> DetectedKey {
        let composition = try await makeComposition(layering: stemURLs)
        let result: MusicUnderstandingSession.SessionResult
        do {
            let session = try await MusicUnderstandingSession(asset: composition)
            result = try await withTaskCancellationHandler {
                try await session.analyze(for: [.key])
            } onCancel: {
                Task { await session.cancel() }
            }
        } catch MusicUnderstandingError.hasProtectedContent {
            throw DetectionError.protectedContent
        } catch MusicUnderstandingError.invalidAsset {
            throw DetectionError.noAudio
        }
        try Task.checkCancellation()
        guard let detected = dominantKey(in: result.key) else {
            throw DetectionError.noKeyFound
        }
        return detected
    }

    @available(macOS 27.0, iOS 27.0, *)
    private static func makeComposition(layering stemURLs: [URL]) async throws -> AVComposition {
        let composition = AVMutableComposition()
        for url in stemURLs {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            guard let sourceTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration),
                  let track = composition.addMutableTrack(
                      withMediaType: .audio,
                      preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                continue
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: .zero)
        }
        guard !composition.tracks.isEmpty, let snapshot = composition.copy() as? AVComposition else {
            throw DetectionError.noAudio
        }
        return snapshot
    }

    /// Sums the time each key holds and returns the longest-held one.
    @available(macOS 27.0, iOS 27.0, *)
    private static func dominantKey(in result: KeyResult?) -> DetectedKey? {
        var secondsByKey: [DetectedKey: Double] = [:]
        for range in result?.ranges ?? [] {
            let detected = DetectedKey(key: SongMusicalKey(tonic: range.value.tonic), mode: range.value.mode == .minor ? .minor : .major)
            secondsByKey[detected, default: 0] += max(range.range.duration.seconds, 0)
        }
        return secondsByKey.max { $0.value < $1.value }?.key
    }
    #endif
}

#if canImport(MusicUnderstanding)
@available(macOS 27.0, iOS 27.0, *)
private extension SongMusicalKey {
    /// Folds enharmonic spellings onto the app's twelve pitch classes.
    init(tonic: KeyResult.Tonic) {
        switch tonic {
        case .c: self = .c
        case .cSharp, .dFlat: self = .cSharp
        case .d: self = .d
        case .dSharp, .eFlat: self = .eFlat
        case .e: self = .e
        case .f: self = .f
        case .fSharp, .gFlat: self = .fSharp
        case .g: self = .g
        case .gSharp, .aFlat: self = .aFlat
        case .a: self = .a
        case .aSharp, .bFlat: self = .bFlat
        case .b: self = .b
        }
    }
}
#endif
