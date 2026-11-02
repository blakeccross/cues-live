import Foundation

/// Spacing between attempts to rebuild the audio output after the device went away.
/// It tops out quickly so a replugged interface is picked up within a couple of seconds.
enum OutputRecoveryBackoff {
    static let initialDelay: TimeInterval = 0.5
    static let maximumDelay: TimeInterval = 2

    /// Delay before attempt `attempt` (0 is the first): 0.5 s, 1 s, then 2 s.
    static func delay(beforeAttempt attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt, 0), 4)
        return min(maximumDelay, initialDelay * pow(2, Double(exponent)))
    }
}
