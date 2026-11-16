import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Stops the enclosing scroll view from moving past its content.
struct TimelineScrollEdgeClamp: View {
    var body: some View {
        TimelineScrollEdgeClampRepresentable()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }
}

#if os(macOS)
private struct TimelineScrollEdgeClampRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> TimelineScrollEdgeClampView {
        TimelineScrollEdgeClampView()
    }

    func updateNSView(_ view: TimelineScrollEdgeClampView, context: Context) {
        view.clampEnclosingScrollView()
    }
}

private final class TimelineScrollEdgeClampView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        clampEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clampEnclosingScrollView()
    }

    override func layout() {
        super.layout()
        clampEnclosingScrollView()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func clampEnclosingScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
    }
}
#else
private struct TimelineScrollEdgeClampRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> TimelineScrollEdgeClampView {
        TimelineScrollEdgeClampView()
    }

    func updateUIView(_ view: TimelineScrollEdgeClampView, context: Context) {
        view.clampEnclosingScrollView()
    }
}

private final class TimelineScrollEdgeClampView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        clampEnclosingScrollView()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clampEnclosingScrollView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clampEnclosingScrollView()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    func clampEnclosingScrollView() {
        var ancestor: UIView? = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                scrollView.bounces = false
                scrollView.alwaysBounceHorizontal = false
                scrollView.alwaysBounceVertical = false
                return
            }
            ancestor = view.superview
        }
    }
}
#endif
