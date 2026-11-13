import Foundation

/// Where one setlist song's summed waveform comes from, and how it is laid onto the song's
/// timeline. Two sources are equal when their `key`s are, so comparing scenes never walks the
/// peaks themselves.
///
/// Local songs read each track through its own clips, as the engine plays them. Remote songs
/// only know one set of clips, so their summed files are mapped through `clips` instead.
struct LiveSetlistWaveformSource: Equatable, Sendable {
    struct Track: Equatable, Sendable {
        let url: URL
        let duration: TimeInterval
        /// The track's own clips, or `nil` when unknown.
        let clips: [TrackClip]?
    }

    let tracks: [Track]
    let precomputedPeaks: [Float]?
    let fileDuration: TimeInterval
    /// Clips that map the summed files onto the timeline when the tracks' own clips are unknown.
    /// Empty when the waveform shows the files as they are: a song without sections or clips.
    let clips: [TrackClip]
    let timelineDuration: TimeInterval
    /// Identity of everything above, for caching the loaded waveform.
    let key: String

    init(_ snapshot: LiveSongWaveformSnapshot) {
        let knowsTrackClips = snapshot.trackClips.count == snapshot.trackSources.count
        tracks = snapshot.trackSources.enumerated().map { index, source in
            Track(
                url: source.url,
                duration: source.duration,
                clips: knowsTrackClips ? snapshot.trackClips[index] : nil
            )
        }
        precomputedPeaks = snapshot.precomputedSourcePeaks
        fileDuration = snapshot.fileDuration
        clips = snapshot.sections.isEmpty ? [] : snapshot.peakClips
        timelineDuration = max(snapshot.timelineDuration, 0.001)

        var hasher = Hasher()
        hasher.combine(snapshot.audioRevision)
        hasher.combine(precomputedPeaks)
        hasher.combine(clips)
        hasher.combine(tracks.map(\.clips))
        let trackKey = tracks.map { "\($0.url.path)|\($0.duration)" }.joined(separator: ";")
        key = "\(trackKey)#\(fileDuration)#\(timelineDuration)#\(hasher.finalize())"
    }

    /// `false` when there is nothing to load, so the lane shows no waveform and no loading line.
    var hasAudio: Bool {
        if let precomputedPeaks {
            return !precomputedPeaks.isEmpty
        }
        return !tracks.isEmpty
    }

    static func == (lhs: LiveSetlistWaveformSource, rhs: LiveSetlistWaveformSource) -> Bool {
        lhs.key == rhs.key
    }

    /// `true` when every track's clips are known, so each is read through its own.
    var readsTrackClips: Bool {
        !tracks.isEmpty && tracks.allSatisfy { $0.clips != nil }
    }

    /// The summed waveform on the song's timeline, as a pyramid. Empty when nothing decoded.
    func loadOverview() async -> WaveformOverview {
        if readsTrackClips {
            return await loadTrackClipsOverview()
        }
        let series = await loadSourceSeries()
        let clips = clips
        let fileDuration = fileDuration
        let timelineDuration = timelineDuration
        return await Task.detached(priority: .utility) {
            let timeline = clips.isEmpty
                ? series
                : WaveformPeakResampler.timelineMinMax(
                    from: series,
                    fileDuration: fileDuration,
                    clips: clips,
                    timelineDuration: timelineDuration
                )
            return timeline.overview()
        }.value
    }

    private func loadTrackClipsOverview() async -> WaveformOverview {
        let timelineTracks = await withTaskGroup(of: WaveformPeakResampler.TimelineTrack.self) { group in
            for track in tracks {
                group.addTask {
                    let overview = await WaveformCache.shared.overview(for: track.url)
                    return .init(overview: overview, clips: track.clips ?? [])
                }
            }
            var loaded: [WaveformPeakResampler.TimelineTrack] = []
            for await track in group {
                loaded.append(track)
            }
            return loaded
        }
        let timelineDuration = timelineDuration
        return await Task.detached(priority: .utility) {
            WaveformPeakResampler.timelineSummedMinMax(
                tracks: timelineTracks,
                timelineDuration: timelineDuration
            ).overview()
        }.value
    }

    /// Min/max from the stems' overviews; failing that, the precomputed or summed magnitude peaks.
    private func loadSourceSeries() async -> WaveformMinMax {
        let sources = tracks.map { (url: $0.url, duration: $0.duration) }
        if !sources.isEmpty {
            let summed = await WaveformCache.shared.summedMinMax(for: sources)
            if !summed.isEmpty {
                return summed
            }
        }
        if let precomputedPeaks {
            return .mirrored(precomputedPeaks)
        }
        return .mirrored(await WaveformCache.shared.summedPeaks(for: sources))
    }
}
