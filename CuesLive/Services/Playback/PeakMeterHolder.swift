import Foundation
import os

final class PeakMeterHolder: @unchecked Sendable {
    /// Fast DAW channel-meter release: 20 dB in 300 ms, so a full-scale peak
    /// falls off a 60 dB scale in about a second. Attack stays immediate.
    private static let releaseDbPerSecond: Float = 20 / 0.3

    private var peak: Float = 0
    private var updatedAt: TimeInterval = 0
    private let lock = OSAllocatedUnfairLock()

    func report(_ value: Float) {
        guard value.isFinite, value > 0 else { return }
        lock.withLock {
            peak = max(peak, value)
        }
    }

    func consume() -> Float {
        let now = Date().timeIntervalSinceReferenceDate
        return lock.withLock {
            let shown = peak
            if updatedAt > 0, peak > 0 {
                let dt = Float(min(max(0, now - updatedAt), 0.25))
                if dt > 0 {
                    peak *= pow(10, -Self.releaseDbPerSecond * dt / 20)
                    if peak < 0.001 { peak = 0 }
                }
            }
            updatedAt = now
            return shown
        }
    }

    func reset() {
        lock.withLock {
            peak = 0
        }
    }
}
