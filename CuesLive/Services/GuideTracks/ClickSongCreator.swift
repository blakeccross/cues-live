import Foundation
import SwiftData

enum ClickSongCreatorError: LocalizedError, Equatable {
    case emptyName
    case invalidBPM

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a song name."
        case .invalidBPM:
            return "Enter a valid tempo."
        }
    }
}

/// Makes a looping song that is only the generated click: no tracks, no audio files.
enum ClickSongCreator {
    static let barCount = 36
    static let sectionName = "Click"

    static func durationForBars(
        _ bars: Int = barCount,
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange]
    ) -> TimeInterval {
        MeasureTiming.timeAtStartOfMeasure(
            bars + 1,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
    }

    @discardableResult
    static func create(
        name: String,
        bpm: Double,
        numerator: Int,
        denominator: Int,
        context: ModelContext
    ) throws -> Song {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClickSongCreatorError.emptyName
        }
        guard bpm.isFinite, bpm > 0 else {
            throw ClickSongCreatorError.invalidBPM
        }

        let clampedBPM = min(
            max(bpm, TempoChange.validBPMRange.lowerBound),
            TempoChange.validBPMRange.upperBound
        )
        let safeNumerator = max(1, numerator)
        let safeDenominator = TimeSignatureChange.validDenominators.contains(denominator)
            ? denominator
            : TimeSignatureChange.defaultDenominator

        let song = Song(name: trimmed)
        song.bpm = clampedBPM
        song.timeSignatureNumerator = safeNumerator
        song.timeSignatureDenominator = safeDenominator
        song.clickSettings = ClickSettings(isEnabled: true)
        context.insert(song)

        do {
            try context.save()
            _ = try SongProjectBridge.ensureProjectFile(for: song, context: context)

            let tempoChanges = SongProjectBridge.defaultTempoChanges(for: song)
            let timeSignatureChanges = SongProjectBridge.defaultTimeSignatureChanges(for: song)
            let duration = durationForBars(
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges
            )

            // No audio: the out point gives the song its length and the generated click plays it.
            var timeline = SongProjectBridge.projectStateOrDefaults(for: song).timeline
            timeline.markers = [
                ArrangementMarker(
                    name: sectionName,
                    startSeconds: 0,
                    sortOrder: 0,
                    loops: true
                )
            ]
            timeline.playRange = SongPlayRange(startSeconds: 0, endSeconds: duration)

            try SongProjectBridge.persist(
                song: song,
                timeline: timeline,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges,
                midiEvents: [],
                context: context
            )

            return song
        } catch {
            context.delete(song)
            try? context.save()
            throw error
        }
    }
}
