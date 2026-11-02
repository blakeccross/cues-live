import Foundation

enum CueTrackGeneratorError: Error {
    case invalidDuration
    case missingSpeechSample(String)
}

enum CueTrackGenerator {
    private static let sampleRate = DecodedStemBuffer.engineSampleRate

    static func generate(
        duration: TimeInterval,
        announcements: [CueAnnouncement],
        speechBuffers: [String: DecodedStemBuffer]
    ) throws -> DecodedStemBuffer {
        guard duration > 0 else { throw CueTrackGeneratorError.invalidDuration }

        let frameCount = Int((duration * sampleRate).rounded(.up))
        let output = try DecodedStemBuffer.silent(frameCount: frameCount, sampleRate: sampleRate)

        for announcement in announcements {
            guard let sample = speechBuffers[announcement.name] else {
                throw CueTrackGeneratorError.missingSpeechSample(announcement.name)
            }
            let startFrame = Int((announcement.announceTime * sampleRate).rounded())
            output.mixAdding(sample, atFrame: startFrame)
        }

        return output
    }
}
