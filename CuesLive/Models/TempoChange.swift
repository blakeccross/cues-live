import Foundation

struct TempoChange: Codable, Identifiable, Hashable {
    static let defaultBPM: Double = 120
    static let validBPMRange = 20.0...999.0

    let id: UUID
    let startMeasure: Int
    let bpm: Double
    let sortOrder: Int

    init(
        id: UUID = UUID(),
        startMeasure: Int,
        bpm: Double,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.startMeasure = startMeasure
        self.bpm = bpm
        self.sortOrder = sortOrder
    }
}

extension Array where Element == TempoChange {
    func activeBPM(atMeasure measure: Int) -> Double {
        active(atMeasure: measure)?.bpm ?? TempoChange.defaultBPM
    }

    var referenceBPM: Double {
        sortedByMeasure.first?.bpm ?? TempoChange.defaultBPM
    }

    func normalizedEnsuringInitialMarker(defaultBPM: Double) -> [TempoChange] {
        let bpm = defaultBPM > 0 ? defaultBPM : TempoChange.defaultBPM
        var changes = sortedByMeasure.filter { $0.startMeasure >= 1 && $0.bpm > 0 }

        if let initialIndex = changes.firstIndex(where: { $0.startMeasure == 1 }) {
            if initialIndex != 0 {
                let initial = changes.remove(at: initialIndex)
                changes.insert(initial, at: 0)
            }
        } else {
            changes.insert(
                TempoChange(startMeasure: 1, bpm: bpm, sortOrder: 0),
                at: 0
            )
        }

        var deduped: [TempoChange] = []
        for change in changes {
            if let last = deduped.last, last.startMeasure == change.startMeasure {
                deduped[deduped.count - 1] = change
            } else {
                deduped.append(change)
            }
        }

        return deduped.enumerated().map { index, change in
            TempoChange(
                id: change.id,
                startMeasure: change.startMeasure,
                bpm: change.bpm,
                sortOrder: index
            )
        }
    }
}
