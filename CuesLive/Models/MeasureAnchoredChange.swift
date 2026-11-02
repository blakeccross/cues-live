import Foundation

/// A tempo or meter change that takes effect from a given measure onward.
protocol MeasureAnchoredChange {
    var startMeasure: Int { get }
    var sortOrder: Int { get }
}

extension TempoChange: MeasureAnchoredChange {}
extension TimeSignatureChange: MeasureAnchoredChange {}

extension Array where Element: MeasureAnchoredChange {
    var sortedByMeasure: [Element] {
        sorted(by: Self.isOrderedBefore)
    }

    /// The change in effect at `measure`: the latest one that has started, or the
    /// earliest one when `measure` precedes them all. Scans without sorting, since
    /// layout code calls this once per measure.
    func active(atMeasure measure: Int) -> Element? {
        lazy
            .filter { $0.startMeasure <= measure }
            .max(by: Self.isOrderedBefore)
            ?? self.min(by: Self.isOrderedBefore)
    }

    private static func isOrderedBefore(_ lhs: Element, _ rhs: Element) -> Bool {
        (lhs.startMeasure, lhs.sortOrder) < (rhs.startMeasure, rhs.sortOrder)
    }
}
