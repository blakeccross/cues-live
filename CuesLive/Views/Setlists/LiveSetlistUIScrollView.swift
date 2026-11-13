#if os(iOS)
import SwiftUI
import UIKit

/// UIKit side of `LiveSetlistScrollHost`: the lane canvas pinned to the viewport, the song lanes'
/// SwiftUI chrome in a hosting controller above it, a playhead line above them, a pinch
/// recognizer that runs alongside panning, and a display link that follows playback.
final class LiveSetlistUIScrollView: UIScrollView, UIScrollViewDelegate {
    var onPinchChanged: (CGFloat) -> Void = { _ in }
    var onPinchEnded: () -> Void = {}

    private let model: LiveSetlistScrollModel
    private let hostingController = UIHostingController(rootView: AnyView(EmptyView()))
    private let playheadView = UIView()
    private let canvasView = LiveSetlistLaneCanvasView(frame: .zero)
    private let pinchDelegate = SimultaneousPinchDelegate()
    private var link: CADisplayLink?

    init(model: LiveSetlistScrollModel) {
        self.model = model
        super.init(frame: .zero)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceVertical = false
        contentInsetAdjustmentBehavior = .never
        delaysContentTouches = false

        hostingController.sizingOptions = []
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        addSubview(canvasView)
        addSubview(hostingController.view)

        playheadView.isUserInteractionEnabled = false
        playheadView.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        playheadView.layer.shadowColor = UIColor.black.cgColor
        playheadView.layer.shadowOpacity = 0.35
        playheadView.layer.shadowRadius = 1
        playheadView.layer.shadowOffset = .zero
        addSubview(playheadView)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))
        pinch.delegate = pinchDelegate
        addGestureRecognizer(pinch)

        model.onLayoutChange = { [weak self] in
            self?.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(rootView: AnyView, scene: LiveSetlistLanePainter.Scene) {
        hostingController.rootView = rootView
        canvasView.update(scene)
        link?.isPaused = false
        reposition()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: max(model.contentWidth, bounds.width), height: bounds.height)
        if contentSize != size {
            contentSize = size
        }
        let hostedFrame = CGRect(origin: .zero, size: size)
        if hostingController.view.frame != hostedFrame {
            hostingController.view.frame = hostedFrame
        }
        model.setViewportWidth(bounds.width)
        reposition()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else {
            hostingController.willMove(toParent: nil)
            hostingController.removeFromParent()
            return
        }
        // Presentations and trait changes from the lanes need a parent controller.
        if hostingController.parent == nil, let parent = enclosingViewController() {
            parent.addChild(hostingController)
            hostingController.didMove(toParent: parent)
        }
        // The link retains its target; leaving the window above breaks that cycle.
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        model.refreshPlayhead()
        reposition()
        // A stopped transport only moves when the owner re-renders, which resumes the link.
        if !model.needsClock {
            link.isPaused = true
        }
    }

    private func reposition() {
        if let target = model.targetOffset() {
            setContentOffset(CGPoint(x: target, y: 0), animated: false)
        }
        if let frame = model.playheadFrame(width: LiveSetlistWaveformMetrics.playheadWidth) {
            playheadView.isHidden = false
            if playheadView.frame != frame {
                playheadView.frame = frame
            }
        } else {
            playheadView.isHidden = true
        }
        // The canvas covers the viewport, so it moves with the scroll offset.
        if canvasView.frame != bounds {
            canvasView.frame = bounds
        }
        canvasView.refresh(from: model, origin: bounds.origin)
    }

    private func enclosingViewController() -> UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            onPinchChanged(recognizer.scale)
        case .ended, .cancelled, .failed:
            onPinchEnded()
        default:
            break
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        model.beginUserScroll()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        model.didScroll(to: contentOffset.x, byUser: isTracking || isDragging || isDecelerating)
        reposition()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            model.endUserScroll()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        model.endUserScroll()
    }
}

/// Lets the pinch run alongside the scroll view's pan and the lanes' tap gestures.
private final class SimultaneousPinchDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
