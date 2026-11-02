import AVFoundation
import Foundation

enum StemAudioWriterError: LocalizedError {
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Could not create output buffer."
        }
    }
}

enum StemAudioWriter {
    static func writeCAF(buffer: DecodedStemBuffer, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let format = buffer.audioFormat
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        let chunkFrames: AVAudioFrameCount = 8_192
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: chunkFrames
        ), let floatChannels = pcmBuffer.floatChannelData else {
            throw StemAudioWriterError.bufferCreationFailed
        }

        var frameOffset = 0
        while frameOffset < buffer.frameCount {
            let framesToWrite = min(Int(chunkFrames), buffer.frameCount - frameOffset)
            pcmBuffer.frameLength = AVAudioFrameCount(framesToWrite)

            for channel in 0..<min(buffer.channelCount, Int(format.channelCount)) {
                let source = buffer.channelPointer(channel).advanced(by: frameOffset)
                floatChannels[channel].update(from: source, count: framesToWrite)
            }

            if buffer.channelCount == 1, format.channelCount >= 2 {
                floatChannels[1].update(from: floatChannels[0], count: framesToWrite)
            }

            try file.write(from: pcmBuffer)
            frameOffset += framesToWrite
        }
    }
}
