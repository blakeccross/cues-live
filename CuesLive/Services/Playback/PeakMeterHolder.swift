import Foundation

/// A track's peak level, reported from the render thread and read by the meter UI.
///
/// The peak is kept as a float's bits in an atomic word, so `report` never waits on the
/// UI. `consume` and `reset` belong to one reading thread.
final class PeakMeterHolder: @unchecked Sendable {
    /// Fast DAW channel-meter release: 20 dB in 300 ms, so a full-scale peak
    /// falls off a 60 dB scale in about a second. Attack stays immediate.
    private static let releaseDbPerSecond: Float = 20 / 0.3

    private let peakBits: UnsafeMutablePointer<UInt64>
    /// Reading thread only.
    private var updatedAt: TimeInterval = 0

    init() {
        peakBits = .allocate(capacity: 1)
        peakBits.initialize(to: 0)
    }

    deinit {
        peakBits.deallocate()
    }

    /// Raises the held peak to `value`. Safe on the render thread.
    func report(_ value: Float) {
        guard value.isFinite, value > 0 else { return }
        let reported = UInt64(value.bitPattern)
        while true {
            let held = realtime_atomic_load_acquire(peakBits)
            guard Float(bitPattern: UInt32(held)) < value else { return }
            if realtime_atomic_compare_exchange(peakBits, held, reported) { return }
        }
    }

    /// The peak to show now; the held peak then decays with the time since the last call.
    func consume() -> Float {
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = updatedAt > 0 ? Float(min(max(0, now - updatedAt), 0.25)) : 0
        updatedAt = now
        while true {
            let held = realtime_atomic_load_acquire(peakBits)
            let shown = Float(bitPattern: UInt32(held))
            var decayed = shown
            if elapsed > 0, decayed > 0 {
                decayed *= pow(10, -Self.releaseDbPerSecond * elapsed / 20)
                if decayed < 0.001 { decayed = 0 }
            }
            // A failed swap means the render thread raised the peak meanwhile; decay that.
            if realtime_atomic_compare_exchange(peakBits, held, UInt64(decayed.bitPattern)) {
                return shown
            }
        }
    }

    func reset() {
        realtime_atomic_store_release(peakBits, 0)
    }
}
