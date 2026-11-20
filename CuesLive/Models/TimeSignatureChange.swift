import Foundation

struct TimeSignatureChange: Codable, Identifiable, Hashable {
    static let defaultNumerator = 4
    static let defaultDenominator = 4
    static let validDenominators = [1, 2, 4, 8, 16]

    let id: UUID
    let numerator: Int
    let denominator: Int
    let startMeasure: Int
    let sortOrder: Int

    init(
        id: UUID = UUID(),
        numerator: Int,
        denominator: Int,
        startMeasure: Int,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.numerator = numerator
        self.denominator = denominator
        self.startMeasure = startMeasure
        self.sortOrder = sortOrder
    }

    var displayName: String {
        "\(numerator)/\(denominator)"
    }
}

extension Array where Element == TimeSignatureChange {
    var referenceNumerator: Int {
        sortedByMeasure.first?.numerator ?? TimeSignatureChange.defaultNumerator
    }

    var referenceDenominator: Int {
        sortedByMeasure.first?.denominator ?? TimeSignatureChange.defaultDenominator
    }

    func normalizedEnsuringInitialMarker(
        defaultNumerator: Int,
        defaultDenominator: Int
    ) -> [TimeSignatureChange] {
        let numerator = defaultNumerator > 0 ? defaultNumerator : TimeSignatureChange.defaultNumerator
        let denominator = defaultDenominator > 0 ? defaultDenominator : TimeSignatureChange.defaultDenominator
        var changes = sortedByMeasure.filter {
            $0.startMeasure >= 1
                && $0.numerator > 0
                && $0.denominator > 0
                && TimeSignatureChange.validDenominators.contains($0.denominator)
        }

        if let initialIndex = changes.firstIndex(where: { $0.startMeasure == 1 }) {
            if initialIndex != 0 {
                let initial = changes.remove(at: initialIndex)
                changes.insert(initial, at: 0)
            }
        } else {
            changes.insert(
                TimeSignatureChange(
                    numerator: numerator,
                    denominator: denominator,
                    startMeasure: 1,
                    sortOrder: 0
                ),
                at: 0
            )
        }

        var deduped: [TimeSignatureChange] = []
        for change in changes {
            if let last = deduped.last, last.startMeasure == change.startMeasure {
                deduped[deduped.count - 1] = change
            } else {
                deduped.append(change)
            }
        }

        return deduped.enumerated().map { index, change in
            TimeSignatureChange(
                id: change.id,
                numerator: change.numerator,
                denominator: change.denominator,
                startMeasure: change.startMeasure,
                sortOrder: index
            )
        }
    }
}
