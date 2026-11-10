import Foundation

/// A tempo or meter change anchored to a bar. Tempo events may also sit partway
/// through the bar; meter changes stay on the downbeat.
protocol MeasureAnchoredChange {
    var startMeasure: Int { get }
    /// Quarter notes after the downbeat. Meter changes are always `0`.
    var beatOffset: Double { get }
    var sortOrder: Int { get }
}

extension TempoChange: MeasureAnchoredChange {}
extension TimeSignatureChange: MeasureAnchoredChange {}

extension TimeSignatureChange {
    var beatOffset: Double { 0 }
}

extension Array where Element: MeasureAnchoredChange {
    var sortedByMeasure: [Element] {
        sorted(by: Self.isOrderedBefore)
    }

    /// The change in effect at the downbeat of `measure`: the latest one that has
    /// already started, or the earliest one when `measure` precedes them all.
    /// A tempo event later in the same bar does not yet apply. Scans without
    /// sorting, since layout code calls this once per measure.
    func active(atMeasure measure: Int) -> Element? {
        lazy
            .filter { $0.startsAtOrBeforeDownbeat(of: measure) }
            .max(by: Self.isOrderedBefore)
            ?? self.min(by: Self.isOrderedBefore)
    }

    private static func isOrderedBefore(_ lhs: Element, _ rhs: Element) -> Bool {
        (lhs.startMeasure, lhs.beatOffset, lhs.sortOrder) < (rhs.startMeasure, rhs.beatOffset, rhs.sortOrder)
    }
}

private extension MeasureAnchoredChange {
    func startsAtOrBeforeDownbeat(of measure: Int) -> Bool {
        startMeasure < measure || (startMeasure == measure && beatOffset <= 0.000_001)
    }
}
