import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ClickTrackGeneratorError: Error {
    case missingAccentSample
    case missingNormalSample
    case invalidDuration
}

enum ClickTrackGenerator {
    private static let sampleRate = DecodedStemBuffer.engineSampleRate
    private static let accentAssetName = "Click Accent"
    private static let normalAssetName = "Click Quarter"

    private static var cachedAccent: DecodedStemBuffer?
    private static var cachedNormal: DecodedStemBuffer?

    static func generate(
        duration: TimeInterval,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        subdivision: ClickTrackSubdivision = .quarter,
        accent: DecodedStemBuffer? = nil,
        normal: DecodedStemBuffer? = nil
    ) throws -> DecodedStemBuffer {
        guard duration > 0 else { throw ClickTrackGeneratorError.invalidDuration }

        let normalizedTempo = tempoChanges.normalizedEnsuringInitialMarker(
            defaultBPM: tempoChanges.referenceBPM
        )
        let normalizedSignatures = timeSignatureChanges.normalizedEnsuringInitialMarker(
            defaultNumerator: MeasureTiming.defaultNumerator,
            defaultDenominator: MeasureTiming.defaultDenominator
        )

        let frameCount = max(1, Int((duration * sampleRate).rounded(.toNearestOrAwayFromZero)))
        let output = try DecodedStemBuffer.silent(frameCount: frameCount, sampleRate: sampleRate)

        let accentSample = try accent ?? sharedAccentSample()
        let normalSample = try normal ?? sharedNormalSample()

        let clicks = ClickTrackScheduler.scheduledClicks(
            from: 0,
            to: duration,
            tempoChanges: normalizedTempo,
            timeSignatureChanges: normalizedSignatures,
            subdivision: subdivision
        )

        for click in clicks {
            let sample = click.isAccent ? accentSample : normalSample
            let startFrame = AudioPlaybackTransport.frameIndex(for: click.time, sampleRate: sampleRate)
            output.mixAdding(sample, atFrame: startFrame)
        }

        return output
    }

    static func sharedAccentSample() throws -> DecodedStemBuffer {
        try accentSample()
    }

    static func sharedNormalSample() throws -> DecodedStemBuffer {
        try normalSample()
    }

    static func resetCachedSamples() {
        cachedAccent = nil
        cachedNormal = nil
    }

    static func loadSample(named assetName: String) throws -> DecodedStemBuffer {
        guard let data = NSDataAsset(name: assetName)?.data, !data.isEmpty else {
            if assetName == accentAssetName {
                throw ClickTrackGeneratorError.missingAccentSample
            }
            throw ClickTrackGeneratorError.missingNormalSample
        }
        return try DecodedStemBuffer.decode(from: data)
    }

    private static func accentSample() throws -> DecodedStemBuffer {
        if let cachedAccent { return cachedAccent }
        let sample = try loadSample(named: accentAssetName)
        cachedAccent = sample
        return sample
    }

    private static func normalSample() throws -> DecodedStemBuffer {
        if let cachedNormal { return cachedNormal }
        let sample = try loadSample(named: normalAssetName)
        cachedNormal = sample
        return sample
    }
}
