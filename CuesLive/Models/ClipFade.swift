import Foundation

/// A fade at one end of a clip. A fade-in rises from silence over `duration`; a fade-out falls
/// to silence over it. Zero `duration` is no fade.
struct ClipFade: Codable, Hashable, Sendable {
    static let none = ClipFade(duration: 0)
    static let curvatureRange = -1.0...1.0

    /// Timeline seconds the fade lasts.
    let duration: TimeInterval
    let shape: ClipFadeShape
    /// Bend of the curve, −1…1. Zero leaves the shape as it is; above zero the fade gets loud sooner.
    let curvature: Double

    private enum CodingKeys: String, CodingKey {
        case duration
        case shape
        case curvature
    }

    /// Values that are not usable are replaced: no fade has one representation, `none`.
    init(duration: TimeInterval, shape: ClipFadeShape = .sCurve, curvature: Double = 0) {
        guard duration.isFinite, duration > 0 else {
            self.duration = 0
            self.shape = .sCurve
            self.curvature = 0
            return
        }
        self.duration = duration
        self.shape = shape
        self.curvature = curvature.isFinite
            ? min(max(curvature, Self.curvatureRange.lowerBound), Self.curvatureRange.upperBound)
            : 0
    }

    var isActive: Bool { duration > 0 }

    /// Fade-in gain at `position` in 0…1 through the fade. The ends stay at silence and unity
    /// whatever the bend. The editor draws this curve and the engine plays it.
    func gain(at position: Double) -> Double {
        let base = shape.gain(at: position)
        guard curvature != 0, base > 0, base < 1 else { return base }
        let weighted = base * pow(2, curvature * 4)
        return weighted / (weighted + 1 - base)
    }

    /// The bend that puts the middle of the fade at `gain`, so a vertical drag follows the pointer.
    func curvature(forMidpointGain gain: Double) -> Double {
        let target = gain.isFinite ? min(max(gain, 0.001), 0.999) : self.gain(at: 0.5)
        let base = shape.gain(at: 0.5)
        let bend = (log2(target / (1 - target)) - log2(base / (1 - base))) / 4
        return min(max(bend, Self.curvatureRange.lowerBound), Self.curvatureRange.upperBound)
    }

    /// This fade, no longer than `clipDuration`.
    func fitted(to clipDuration: TimeInterval) -> ClipFade {
        guard duration > clipDuration else { return self }
        return ClipFade(duration: clipDuration, shape: shape, curvature: curvature)
    }

    func with(duration: TimeInterval) -> ClipFade {
        ClipFade(duration: duration, shape: shape, curvature: curvature)
    }

    func with(shape: ClipFadeShape) -> ClipFade {
        ClipFade(duration: duration, shape: shape, curvature: curvature)
    }

    func with(curvature: Double) -> ClipFade {
        ClipFade(duration: duration, shape: shape, curvature: curvature)
    }

    /// Gain of a clip's fades `offset` timeline seconds into it: 0…1, unity between the fades.
    /// Where the two overlap they multiply.
    static func envelope(
        atOffset offset: TimeInterval,
        clipDuration: TimeInterval,
        fadeIn: ClipFade,
        fadeOut: ClipFade
    ) -> Double {
        var gain = 1.0
        if fadeIn.duration > 0, offset < fadeIn.duration {
            gain *= fadeIn.gain(at: offset / fadeIn.duration)
        }
        let remaining = clipDuration - offset
        if fadeOut.duration > 0, remaining < fadeOut.duration {
            gain *= fadeOut.gain(at: remaining / fadeOut.duration)
        }
        return gain
    }
}

extension ClipFade {
    /// A shape this version does not know falls back to the default curve, so the file still opens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shapeName = try container.decodeIfPresent(String.self, forKey: .shape)
        self.init(
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0,
            shape: shapeName.flatMap(ClipFadeShape.init(rawValue:)) ?? .sCurve,
            curvature: try container.decodeIfPresent(Double.self, forKey: .curvature) ?? 0
        )
    }
}
