import Foundation

/// Labeled spacing stays wide enough to read; unlabeled ticks subdivide it.
struct TimelineTimeRulerScale {
    var major: TimeInterval
    var minor: TimeInterval

    init(pixelsPerSecond: CGFloat) {
        let pps = max(pixelsPerSecond, 0.001)
        let majors: [TimeInterval] = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let raw = Double(140 / pps)
        major = majors.first(where: { $0 >= raw - 0.000_1 }) ?? 600
        let candidate = Self.preferredMinor(for: major)
        minor = CGFloat(candidate) * pps >= 8 ? candidate : major
    }

    /// Minutes and seconds, with as many decimals as the labeled spacing needs.
    func label(for value: TimeInterval) -> String {
        let clamped = max(0, value)
        let minutes = Int(clamped) / 60
        let seconds = clamped - Double(minutes * 60)
        if major < 0.01 {
            return String(format: "%d:%06.3f", minutes, seconds)
        }
        if major < 0.1 {
            return String(format: "%d:%05.2f", minutes, seconds)
        }
        if major < 1 {
            return String(format: "%d:%04.1f", minutes, seconds)
        }
        let wholeSeconds = Int((seconds + 0.000_1).rounded(.down))
        return String(format: "%d:%02d", minutes, wholeSeconds)
    }

    private static func preferredMinor(for major: TimeInterval) -> TimeInterval {
        switch major {
        case 0.001: return 0.000_2
        case 0.002: return 0.000_5
        case 0.005: return 0.001
        case 0.01: return 0.002
        case 0.02: return 0.005
        case 0.05: return 0.01
        case 0.1: return 0.02
        case 0.2: return 0.05
        case 0.5: return 0.1
        case 1: return 0.2
        case 2: return 0.5
        case 5: return 1
        case 10: return 2
        case 15: return 5
        case 30: return 5
        case 60: return 10
        case 120: return 30
        case 300: return 60
        default: return 120
        }
    }
}
