import Foundation

/// Curve a clip fade follows. `gain(at:)` is the fade-in curve; a fade-out reads it backwards.
enum ClipFadeShape: String, Codable, CaseIterable, Sendable {
    case linear
    /// Constant power, for fading between unrelated material.
    case equalPower
    case sCurve
    case exponential
    case logarithmic

    var label: String {
        switch self {
        case .linear: return "Linear"
        case .equalPower: return "Equal Power"
        case .sCurve: return "S-Curve"
        case .exponential: return "Exponential"
        case .logarithmic: return "Logarithmic"
        }
    }

    /// Fade-in gain at `position` in 0…1: silent at 0, unity at 1. A value that is not a number is silent.
    func gain(at position: Double) -> Double {
        let t = position.isNaN ? 0 : min(max(position, 0), 1)
        switch self {
        case .linear: return t
        case .equalPower: return sin(t * .pi / 2)
        case .sCurve: return 0.5 - 0.5 * cos(t * .pi)
        case .exponential: return t * t * t
        case .logarithmic: return 1 - (1 - t) * (1 - t) * (1 - t)
        }
    }
}
