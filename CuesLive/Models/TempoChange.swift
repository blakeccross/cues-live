import Foundation

struct TempoChange: Codable, Identifiable, Hashable {
    static let defaultBPM: Double = 120
    static let validBPMRange = 20.0...999.0
    /// Quarter-note resolution. SoundCraft uses the same 960 ticks per quarter.
    static let ticksPerQuarter = 960

    let id: UUID
    let startMeasure: Int
    /// Quarter notes after this bar's downbeat. Zero sits on the bar line.
    let beatOffset: Double
    let bpm: Double
    let sortOrder: Int

    init(
        id: UUID = UUID(),
        startMeasure: Int,
        beatOffset: Double = 0,
        bpm: Double,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.startMeasure = startMeasure
        self.beatOffset = beatOffset.isFinite ? max(0, beatOffset) : 0
        self.bpm = bpm
        self.sortOrder = sortOrder
    }

    var isDownbeat: Bool { beatOffset <= 0.000_001 }

    /// The opening tempo of the song. It is the one marker that cannot be removed.
    var isOrigin: Bool { startMeasure <= 1 && isDownbeat }

    var positionLabel: String {
        if isDownbeat {
            return "Measure \(startMeasure)"
        }
        let beatNumber = beatOffset + 1
        if abs(beatNumber.rounded() - beatNumber) < 0.001 {
            return "Measure \(startMeasure), Beat \(Int(beatNumber.rounded()))"
        }
        return String(format: "Measure %d + %.2f beats", startMeasure, beatOffset)
    }

    func occupiesSamePosition(as other: TempoChange) -> Bool {
        startMeasure == other.startMeasure && abs(beatOffset - other.beatOffset) <= 0.000_001
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startMeasure
        case beatOffset
        case bpm
        case sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startMeasure = try container.decode(Int.self, forKey: .startMeasure)
        let decodedOffset = try container.decodeIfPresent(Double.self, forKey: .beatOffset) ?? 0
        beatOffset = decodedOffset.isFinite ? max(0, decodedOffset) : 0
        bpm = try container.decode(Double.self, forKey: .bpm)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startMeasure, forKey: .startMeasure)
        try container.encode(beatOffset, forKey: .beatOffset)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(sortOrder, forKey: .sortOrder)
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

        if !changes.contains(where: \.isOrigin) {
            changes.insert(
                TempoChange(startMeasure: 1, bpm: bpm, sortOrder: 0),
                at: 0
            )
        }

        var deduped: [TempoChange] = []
        for change in changes {
            if let last = deduped.last, last.occupiesSamePosition(as: change) {
                deduped[deduped.count - 1] = change
            } else {
                deduped.append(change)
            }
        }

        return deduped.enumerated().map { index, change in
            TempoChange(
                id: change.id,
                startMeasure: change.startMeasure,
                beatOffset: change.beatOffset,
                bpm: change.bpm,
                sortOrder: index
            )
        }
    }
}
