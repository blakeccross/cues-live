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

enum ClickSongCreator {
    static let barCount = 8
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

            try ClickTrackFileGenerator.generateAndAttach(
                to: song,
                context: context,
                duration: duration,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges
            )

            let marker = ArrangementMarker(
                name: sectionName,
                startSeconds: 0,
                sortOrder: 0
            )
            let slot = ArrangementSlot(markerID: marker.id)

            try SongProjectBridge.persist(
                song: song,
                markers: [marker],
                arrangementSlots: [slot],
                clipTrims: [],
                removedClips: [],
                clipGaps: [],
                clipRegions: [],
                loopSlotIDs: [slot.id],
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
