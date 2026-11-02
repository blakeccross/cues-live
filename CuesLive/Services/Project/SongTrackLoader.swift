import Foundation

enum SongTrackLoader {
    typealias TrackInput = (
        id: UUID,
        url: URL,
        relativePath: String,
        settings: AudioEngineManager.TrackSettings,
        groupID: UUID?
    )

    struct CachedDecodedTrack {
        let relativePath: String
        let sourceModificationDate: Date
        let buffer: DecodedStemBuffer
    }

    static func trackInputs(for song: Song) -> [TrackInput] {
        song.sortedTracks.compactMap { track in
            guard let url = FileStore.trackURL(for: song, track: track) else { return nil }
            return (
                id: track.id,
                url: url,
                relativePath: track.mediaPath ?? track.relativeFilePath,
                settings: AudioEngineManager.TrackSettings(track: track),
                groupID: track.group?.id
            )
        }
    }

    static func sourceModificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    static func sourceModificationDates(for inputs: [TrackInput]) -> [UUID: Date] {
        Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, sourceModificationDate(for: $0.url)) })
    }

    static func decodeTracks(
        inputs: [TrackInput],
        sourceModificationDates: [UUID: Date],
        decodedBufferCache: [UUID: CachedDecodedTrack] = [:]
    ) async throws -> [UUID: DecodedStemBuffer] {
        let maxConcurrent = max(1, ProcessInfo.processInfo.processorCount)

        return try await withThrowingTaskGroup(of: (UUID, DecodedStemBuffer).self) { group in
            var nextIndex = 0

            func enqueueNext() {
                guard nextIndex < inputs.count else { return }
                let input = inputs[nextIndex]
                nextIndex += 1

                group.addTask {
                    try Task.checkCancellation()
                    let modificationDate = sourceModificationDates[input.id] ?? .distantPast
                    if let cached = decodedBufferCache[input.id],
                       cached.relativePath == input.relativePath,
                       cached.sourceModificationDate == modificationDate {
                        return (input.id, cached.buffer)
                    }

                    let buffer = try DecodedStemBuffer.decode(from: input.url)
                    return (input.id, buffer)
                }
            }

            for _ in 0..<min(maxConcurrent, inputs.count) {
                enqueueNext()
            }

            var buffers: [UUID: DecodedStemBuffer] = [:]
            buffers.reserveCapacity(inputs.count)

            while let (trackID, buffer) = try await group.next() {
                buffers[trackID] = buffer
                enqueueNext()
            }

            return buffers
        }
    }

    static func prepareTrackPayloads(
        inputs: [TrackInput],
        decodedBuffers: [UUID: DecodedStemBuffer],
        sourceModificationDates: [UUID: Date],
        bakePitchShift: Bool,
        bakeCache: TrackBakeCache = .shared
    ) async throws -> [AudioEngineManager.PreparedTrackPayload] {
        let maxConcurrent = max(1, ProcessInfo.processInfo.processorCount)

        return try await withThrowingTaskGroup(
            of: (Int, AudioEngineManager.PreparedTrackPayload).self
        ) { group in
            var nextIndex = 0

            func enqueueNext() {
                guard nextIndex < inputs.count else { return }
                let index = nextIndex
                nextIndex += 1
                let input = inputs[index]

                group.addTask {
                    try Task.checkCancellation()
                    guard let decodedBuffer = decodedBuffers[input.id] else {
                        throw CancellationError()
                    }

                    let modificationDate = sourceModificationDates[input.id] ?? .distantPast
                    let semitones = Int((input.settings.pitchCents / 100).rounded())

                    let payload = try autoreleasepool {
                        if bakePitchShift,
                           semitones != 0,
                           !input.settings.excludeFromTranspose,
                           let cached = bakeCache.lookup(
                               trackID: input.id,
                               relativePath: input.relativePath,
                               sourceModificationDate: modificationDate,
                               semitones: semitones
                           ) {
                            var cachedSettings = input.settings
                            cachedSettings.pitchCents = 0
                            return try AudioEngineManager.prepareTrackPayload(
                                id: input.id,
                                decodedBuffer: cached,
                                settings: cachedSettings,
                                groupID: input.groupID,
                                bakePitchShift: false
                            )
                        }

                        let prepared = try AudioEngineManager.prepareTrackPayload(
                            id: input.id,
                            decodedBuffer: decodedBuffer,
                            settings: input.settings,
                            groupID: input.groupID,
                            bakePitchShift: bakePitchShift
                        )

                        if bakePitchShift,
                           semitones != 0,
                           !input.settings.excludeFromTranspose,
                           let bakedBuffer = prepared.buffer as? DecodedStemBuffer {
                            bakeCache.store(
                                trackID: input.id,
                                relativePath: input.relativePath,
                                sourceModificationDate: modificationDate,
                                semitones: semitones,
                                buffer: bakedBuffer
                            )
                        }

                        return prepared
                    }

                    return (index, payload)
                }
            }

            for _ in 0..<min(maxConcurrent, inputs.count) {
                enqueueNext()
            }

            var prepared = [AudioEngineManager.PreparedTrackPayload?](
                repeating: nil,
                count: inputs.count
            )

            while let (index, payload) = try await group.next() {
                prepared[index] = payload
                enqueueNext()
            }

            guard prepared.allSatisfy({ $0 != nil }) else {
                throw CancellationError()
            }

            return prepared.map { $0! }
        }
    }

    /// Live/setlist playback payloads. Prefers valid baked group stems when available;
    /// edit mode should continue to use `trackInputs` / `streamingPayloads` directly.
    static func playbackPayloads(
        for song: Song,
        preferBaked: Bool = true
    ) throws -> [AudioEngineManager.PreparedTrackPayload] {
        if preferBaked, let baked = try bakedPlaybackPayloads(for: song) {
            return baked
        }

        let trackInputs = trackInputs(for: song)
        return try streamingPayloads(trackInputs: trackInputs)
    }

    static func bakedPlaybackPayloads(for song: Song) throws -> [AudioEngineManager.PreparedTrackPayload]? {
        guard SongBakeStore.hasValidBake(for: song),
              let manifest = SongBakeStore.manifest(for: song) else {
            return nil
        }

        var payloads: [AudioEngineManager.PreparedTrackPayload] = []
        payloads.reserveCapacity(manifest.groupStems.count)

        for stem in manifest.groupStems {
            guard let url = SongBakeStore.bakedStemURL(for: song, relativePath: stem.relativePath) else {
                return nil
            }

            let buffer = try StreamingStemBuffer(url: url)
            let settings = AudioEngineManager.TrackSettings(
                volume: 1,
                isMuted: false,
                isSolo: false,
                trimStart: 0,
                trimEnd: stem.duration,
                pitchCents: 0,
                excludeFromTranspose: true,
                ignoresSolo: true,
                bypassesArrangementMapping: true
            )

            payloads.append(
                AudioEngineManager.PreparedTrackPayload(
                    id: stem.playbackTrackID,
                    buffer: buffer,
                    settings: settings,
                    groupID: stem.groupID
                )
            )
        }

        guard !payloads.isEmpty else { return nil }
        return payloads
    }

    /// Builds payloads that stream their audio from disk on demand instead of
    /// decoding the entire stem into memory. This is cheap (it only opens each
    /// file and reads its header), so songs become near-instant to load.
    ///
    /// Pitch is applied in real time by the engine's time-pitch node rather than
    /// being baked offline, so high-quality transpose isn't pre-rendered here.
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

    static func timelineDuration(
        for song: Song,
        sourceDurationForTrack: @escaping (UUID) -> TimeInterval
    ) -> TimeInterval {
        let projectState = SongProjectBridge.projectStateOrDefaults(for: song)
        let markers = projectState.markers
        let arrangement = projectState.arrangement
        let inputs = SongArrangementStore.makeLayoutInputs(
            markers: markers,
            trackIDs: song.sortedTracks.map(\.id),
            sourceDurationForTrack: sourceDurationForTrack
        )
        let layout = SongArrangementStore.buildLayoutSnapshot(
            slots: arrangement.slots,
            clipTrims: arrangement.clipTrims,
            removedClips: arrangement.removedClips,
            clipGaps: arrangement.clipGaps,
            clipRegions: arrangement.clipRegions,
            inputs: inputs
        )

        return SongArrangementStore.effectiveTimelineDuration(
            rulerSections: layout.rulerSections,
            trackSections: layout.trackSections
        )
    }
}
