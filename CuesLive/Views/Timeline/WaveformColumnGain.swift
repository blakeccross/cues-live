import CoreGraphics
import Foundation

/// Gain a waveform is drawn at: one level, shaped by the clip's fades where it has any.
struct WaveformColumnGain: Equatable {
    /// A clip's fades and where the clip sits, in content points.
    struct Fades: Equatable {
        let startX: CGFloat
        let width: CGFloat
        let duration: TimeInterval
        let fadeIn: ClipFade
        let fadeOut: ClipFade
    }

    var level: Float = 1
    var fades: Fades?

    /// Gain at content x.
    func value(atX x: CGFloat) -> Float {
        guard let fades, fades.width > 0 else { return level }
        let offset = Double((x - fades.startX) / fades.width) * fades.duration
        let envelope = ClipFade.envelope(
            atOffset: offset,
            clipDuration: fades.duration,
            fadeIn: fades.fadeIn,
            fadeOut: fades.fadeOut
        )
        return level * Float(envelope)
    }
}
