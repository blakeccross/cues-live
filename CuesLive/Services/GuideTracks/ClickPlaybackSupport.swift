import Foundation
import os
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Loads a song's generated click into the engine beside its stems. The click is not a track:
/// it plays from the tempo map, follows the Click group's fader and output, and ignores solo.
enum ClickPlaybackSupport {
    static let payloadID = UUID(uuidString: "00000000-0000-4000-8000-00000000C11C")!

    enum SoundError: Error {
        case missingSample(assetName: String)
    }

    private static let logger = Logger(subsystem: "live.cues", category: "Click")

    /// Every song carries the click source, silent while the click is off, so turning it on
    /// or editing the tempo only swaps its pattern instead of rebuilding the audio graph.
    private static func makePayload(
        settings: ClickSettings,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        duration: TimeInterval,
        groupID: UUID?
    ) -> AudioEngineManager.PreparedTrackPayload? {
        guard duration > 0 else { return nil }
        let pattern = makePattern(
            settings: settings,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            duration: duration
        )
        guard let source = try? ProceduralClickSource(pattern: pattern) else { return nil }
        return AudioEngineManager.PreparedTrackPayload(
            id: payloadID,
            buffer: source,
            settings: trackSettings(duration: duration),
            groupID: groupID
        )
    }

    static func appendPayload(
        to payloads: inout [AudioEngineManager.PreparedTrackPayload],
        for song: Song,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        duration: TimeInterval
    ) {
        guard let payload = makePayload(
            settings: song.clickSettings,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            duration: duration,
            groupID: song.modelContext.flatMap(resolveGroupID(in:))
        ) else {
            return
        }
        payloads.removeAll { $0.id == payloadID }
        payloads.append(payload)
    }

    /// Brings the loaded click in line with new settings, tempo map or song length.
    static func refresh(
        in engine: AudioEngineManager,
        settings: ClickSettings,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) {
        guard let loaded = engine.loadedClick else { return }
        let duration = engine.duration
        let current = loaded.source.currentPattern
        let key = ProceduralClickSource.Pattern.Key(
            settings: settings,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            duration: duration
        )
        if current.key != key {
            // A tempo, rhythm or length edit keeps the sounds, so reuse the hits it already has.
            let hasSameHits = current.key?.settings.hasSameHits(as: settings) == true
                && !current.hits.accent.isEmpty
            loaded.source.setPattern(makePattern(
                settings: settings,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                duration: duration,
                hits: hasSameHits ? current.hits : nil
            ))
        }
        if duration > 0, loaded.settings.trimEnd != duration {
            engine.updateTrackSettings(id: payloadID, settings: trackSettings(duration: duration))
        }
    }

    /// - Parameter hits: The sound's samples when already loaded; nil loads them from the assets.
    static func makePattern(
        settings: ClickSettings,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        duration: TimeInterval,
        hits loadedHits: ProceduralClickSource.Hits? = nil
    ) -> ProceduralClickSource.Pattern {
        let key = ProceduralClickSource.Pattern.Key(
            settings: settings,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            duration: duration
        )
        guard settings.isEnabled, duration > 0 else {
            return ProceduralClickSource.Pattern(key: key)
        }
        let hits: ProceduralClickSource.Hits
        do {
            hits = try loadedHits ?? self.hits(for: settings)
        } catch {
            let samples = "\(settings.accentSample.rawValue), \(settings.beatSample.rawValue)"
            logger.error("Click samples \(samples, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
            return .silent
        }

        let sampleRate = DecodedStemBuffer.engineSampleRate
        let clicks = ClickScheduler.scheduledClicks(
            from: 0,
            to: duration,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges,
            rhythm: settings.rhythm
        )
        let events = clicks.map { click in
            ProceduralClickSource.Event(
                frame: AudioPlaybackTransport.frameIndex(for: click.time, sampleRate: sampleRate),
                isAccent: click.isAccent
            )
        }
        return ProceduralClickSource.Pattern(key: key, events: events, hits: hits)
    }

    static func resolveGroupID(in context: ModelContext) -> UUID? {
        TrackGroupStore.ensureDefaults(in: context)
        return TrackGroupStore.findOrCreateGroup(named: TrackGroupStore.clickGroupName, in: context)?.id
    }

    private static func trackSettings(duration: TimeInterval) -> AudioEngineManager.TrackSettings {
        AudioEngineManager.TrackSettings(
            volume: 1,
            isMuted: false,
            isSolo: false,
            trimStart: 0,
            trimEnd: duration,
            ignoresSolo: true,
            bypassesArrangementMapping: true
        )
    }

    /// The accent and beat hits from the asset catalog, each at its own volume.
    static func hits(for settings: ClickSettings) throws -> ProceduralClickSource.Hits {
        ProceduralClickSource.Hits(
            accent: try samples(
                assetName: settings.accentSample.assetName,
                gain: Float(settings.accentVolume)
            ),
            normal: try samples(
                assetName: settings.beatSample.assetName,
                gain: Float(settings.beatVolume)
            )
        )
    }

    private static func samples(assetName: String, gain: Float) throws -> [Float] {
        guard let data = NSDataAsset(name: assetName)?.data, !data.isEmpty else {
            throw SoundError.missingSample(assetName: assetName)
        }
        let buffer = try DecodedStemBuffer.decode(from: data)
        var samples = [Float](repeating: 0, count: buffer.frameCount)
        samples.withUnsafeMutableBufferPointer { destination in
            guard let base = destination.baseAddress else { return }
            buffer.copy(
                channel: 0,
                startingFrame: 0,
                frameCount: buffer.frameCount,
                into: base,
                destinationOffset: 0,
                gain: gain
            )
        }
        return samples
    }
}
