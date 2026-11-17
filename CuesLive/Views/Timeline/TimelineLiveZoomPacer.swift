#if os(macOS)
import AppKit
import QuartzCore

/// Collects zoom input and applies it once per display refresh, like SoundCraft, so a pinch
/// draws exactly one step a frame however its events fall between frames.
///
/// Trackpad events arrive on their own clock. Drawing on every event drew twice in some frames
/// and not at all in others. The display link also asks for the display's full rate, so a
/// ProMotion screen runs at 120 Hz while the zoom moves.
@MainActor
final class TimelineLiveZoomPacer: NSObject {
    /// Frames the link keeps running after the last event, so a pinch that slows down does not
    /// wait a frame for the link to start again.
    private static let idleFrames = 12

    private var scale: CGFloat = 1
    private var anchorX: CGFloat = 0
    private var idleFrameCount = 0
    private var link: CADisplayLink?
    private weak var view: NSView?
    /// Applies the zoom collected since the last frame.
    private let apply: (CGFloat, CGFloat) -> Void

    init(view: NSView, apply: @escaping (CGFloat, CGFloat) -> Void) {
        self.view = view
        self.apply = apply
    }

    /// Multiplies the zoom by `factor` at the next frame, keeping viewport x `anchorX` in place.
    func add(_ factor: CGFloat, anchorX: CGFloat) {
        scale *= factor
        self.anchorX = anchorX
        idleFrameCount = 0
        startLink()
    }

    /// Applies any zoom still waiting for a frame, for the end of a gesture.
    func flush() {
        guard scale != 1 else { return }
        let factor = scale
        scale = 1
        apply(factor, anchorX)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func startLink() {
        if let link {
            link.isPaused = false
            return
        }
        guard let view else { return }
        let link = view.displayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        guard scale != 1 else {
            idleFrameCount += 1
            if idleFrameCount >= Self.idleFrames {
                link.isPaused = true
            }
            return
        }
        flush()
    }
}
#endif
