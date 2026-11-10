import Foundation

enum KeyChangeRenderer {
    struct Progress: Sendable {
        var trackName: String
        var completed: Int
        var total: Int
    }

    enum RenderError: LocalizedError {
        case missingProject
        case missingMedia(String)
        case pitchFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingProject:
                return "This song does not have a project file."
            case .missingMedia(let name):
                return "Could not find audio for \(name)."
            case .pitchFailed(let name):
                return "Could not pitch-shift \(name)."
            }
        }
    }

    struct Job: Sendable {
        var trackName: String
        var sourceURL: URL
        var outputURL: URL
        var semitones: Int
    }

    /// Rewrites the song's `Pitched` folder from the original stems.
    @MainActor
    static func bake(
        song: Song,
        onProgress: @escaping @MainActor (Progress) -> Void
    ) async throws {
        guard let projectURL = SongProjectBridge.projectURL(for: song) else {
            throw RenderError.missingProject
        }

        let semitones = song.transposeSemitones
        PitchedStemStore.removeAll(projectURL: projectURL)
        guard semitones != 0 else {
            onProgress(Progress(trackName: "", completed: 0, total: 0))
            return
        }

        var jobs: [Job] = []
        for track in song.sortedTracks where track.includeInKeyChange {
            guard let sourceURL = FileStore.trackURL(for: song, track: track) else {
                throw RenderError.missingMedia(track.displayName)
            }
            jobs.append(
                Job(
                    trackName: track.displayName,
                    sourceURL: sourceURL,
                    outputURL: PitchedStemStore.fileURL(
                        trackID: track.id,
                        semitones: semitones,
                        projectURL: projectURL
                    ),
                    semitones: semitones
                )
            )
        }

        for (index, job) in jobs.enumerated() {
            onProgress(Progress(trackName: job.trackName, completed: index, total: jobs.count))
            try await Task.detached(priority: .userInitiated) {
                try render(job)
            }.value
        }
        onProgress(Progress(trackName: "", completed: jobs.count, total: jobs.count))
    }

    /// Returns the baked file when this track should play shifted, rendering it if it is missing.
    static func ensureBakedFile(for track: AudioTrack, song: Song) throws -> URL? {
        guard song.transposeSemitones != 0, track.includeInKeyChange else { return nil }
        guard let projectURL = SongProjectBridge.projectURL(for: song) else { return nil }
        let outputURL = PitchedStemStore.fileURL(
            trackID: track.id,
            semitones: song.transposeSemitones,
            projectURL: projectURL
        )
        guard let sourceURL = FileStore.trackURL(for: song, track: track) else { return nil }
        if FileManager.default.fileExists(atPath: outputURL.path), !isNewer(sourceURL, than: outputURL) {
            return outputURL
        }
        try render(
            Job(
                trackName: track.displayName,
                sourceURL: sourceURL,
                outputURL: outputURL,
                semitones: song.transposeSemitones
            )
        )
        return outputURL
    }

    private static func isNewer(_ sourceURL: URL, than outputURL: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let sourceDate = try? sourceURL.resourceValues(forKeys: keys).contentModificationDate
        let outputDate = try? outputURL.resourceValues(forKeys: keys).contentModificationDate
        guard let sourceDate, let outputDate else { return true }
        return sourceDate > outputDate
    }

    static func render(_ job: Job) throws {
        let didAccess = job.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                job.sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let decoded = try DecodedStemBuffer.decode(from: job.sourceURL)
        let pitched = try PitchShifter.shift(decoded, semitones: job.semitones)
        try StemAudioWriter.writeCAF(buffer: pitched, to: job.outputURL)
    }
}

enum PitchShifter {
    static func shift(_ buffer: DecodedStemBuffer, semitones: Int) throws -> DecodedStemBuffer {
        guard semitones != 0 else { return buffer }
        let output = try DecodedStemBuffer.silent(
            frameCount: buffer.frameCount,
            sampleRate: buffer.sampleRate,
            channelCount: buffer.channelCount
        )

        let inputPointers: [UnsafePointer<Float>?] = (0..<buffer.channelCount).map { buffer.channelPointer($0) }
        let outputPointers: [UnsafeMutablePointer<Float>?] = (0..<output.channelCount).map { output.mutableChannelPointer($0) }
        let succeeded = inputPointers.withUnsafeBufferPointer { inputs in
            outputPointers.withUnsafeBufferPointer { outputs in
                pitch_shift_offline(
                    inputs.baseAddress,
                    outputs.baseAddress,
                    Int32(buffer.channelCount),
                    Int32(buffer.frameCount),
                    buffer.sampleRate,
                    Int32(semitones)
                )
            }
        }
        guard succeeded else {
            throw KeyChangeRenderer.RenderError.pitchFailed("audio")
        }
        return output
    }
}
