import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Shifts the waveform scroll view so a zoom keeps the playhead under the same
/// screen position. SwiftUI's scroll view otherwise keeps its point offset while
/// the lanes grow, which slides the playhead sideways.
struct LiveSetlistZoomScrollAdjuster: View {
    var batchID: Int?
    var delta: CGFloat

    var body: some View {
        #if os(macOS)
        LiveSetlistZoomScrollAdjusterMac(batchID: batchID, delta: delta)
        #else
        LiveSetlistZoomScrollAdjusterIOS(batchID: batchID, delta: delta)
        #endif
    }
}

private struct LiveSetlistZoomScrollMetrics {
    var offset: CGFloat
    var minimum: CGFloat
    var maximum: CGFloat
    var contentWidth: CGFloat
}

/// Retry loop shared by the macOS and iOS scroll adjusters.
private final class LiveSetlistZoomScrollDriver {
    private var session = LiveSetlistZoomScrollSession()
    private var batchID: Int?
    private var delta: CGFloat = 0
    private var retryScheduled = false
    private var retryCount = 0
    private var isApplying = false

    var needsLayoutPass: Bool {
        batchID != nil || session.unclampedTarget != nil
    }

    func sync(
        batchID: Int?,
        delta: CGFloat,
        readMetrics: @escaping () -> LiveSetlistZoomScrollMetrics?,
        setOffset: @escaping (CGFloat) -> Void
    ) {
        if batchID != self.batchID || delta != self.delta {
            retryCount = 0
        }
        self.batchID = batchID
        self.delta = delta
        let settled = apply(allowStable: batchID == nil, readMetrics: readMetrics, setOffset: setOffset)
        if !settled {
            scheduleRetry(readMetrics: readMetrics, setOffset: setOffset)
        }
    }

    func applyFromLayout(
        readMetrics: () -> LiveSetlistZoomScrollMetrics?,
        setOffset: (CGFloat) -> Void
    ) {
        guard needsLayoutPass else { return }
        apply(allowStable: batchID == nil, readMetrics: readMetrics, setOffset: setOffset)
    }

    private func scheduleRetry(
        readMetrics: @escaping () -> LiveSetlistZoomScrollMetrics?,
        setOffset: @escaping (CGFloat) -> Void
    ) {
        guard !retryScheduled, retryCount < LiveSetlistZoomScrollSession.maximumStableAttempts else { return }
        retryScheduled = true
        retryCount += 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            let settled = self.apply(
                allowStable: self.batchID == nil,
                readMetrics: readMetrics,
                setOffset: setOffset
            )
            if !settled {
                self.scheduleRetry(readMetrics: readMetrics, setOffset: setOffset)
            }
        }
    }

    @discardableResult
    private func apply(
        allowStable: Bool,
        readMetrics: () -> LiveSetlistZoomScrollMetrics?,
        setOffset: (CGFloat) -> Void
    ) -> Bool {
        guard !isApplying else { return session.reachedTarget }
        guard let metrics = readMetrics() else {
            return batchID == nil && session.unclampedTarget == nil
        }
        isApplying = true
        let update = session.update(
            batchID: batchID,
            delta: delta,
            actualOffset: metrics.offset,
            minimumOffset: metrics.minimum,
            maximumOffset: metrics.maximum,
            contentWidth: metrics.contentWidth,
            allowStable: allowStable
        )
        if let offset = update.offset {
            setOffset(offset)
        }
        isApplying = false
        return update.isSettled
    }
}

#if os(macOS)
private struct LiveSetlistZoomScrollAdjusterMac: NSViewRepresentable {
    var batchID: Int?
    var delta: CGFloat

    func makeNSView(context: Context) -> LiveSetlistZoomScrollAdjusterMacView {
        let view = LiveSetlistZoomScrollAdjusterMacView()
        view.sync(batchID: batchID, delta: delta)
        return view
    }

    func updateNSView(_ nsView: LiveSetlistZoomScrollAdjusterMacView, context: Context) {
        nsView.sync(batchID: batchID, delta: delta)
    }
}

private final class LiveSetlistZoomScrollAdjusterMacView: NSView {
    private let driver = LiveSetlistZoomScrollDriver()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        driver.applyFromLayout(
            readMetrics: { self.scrollMetrics() },
            setOffset: { self.setOffset($0) }
        )
    }

    func sync(batchID: Int?, delta: CGFloat) {
        driver.sync(
            batchID: batchID,
            delta: delta,
            readMetrics: { [weak self] in self?.scrollMetrics() },
            setOffset: { [weak self] in self?.setOffset($0) }
        )
    }

    private func scrollMetrics() -> LiveSetlistZoomScrollMetrics? {
        guard let scrollView = enclosingScrollView else { return nil }
        let clip = scrollView.contentView
        let contentWidth = scrollView.documentView?.frame.width ?? clip.bounds.width
        let maximum = max(0, contentWidth - clip.bounds.width)
        return LiveSetlistZoomScrollMetrics(
            offset: clip.bounds.origin.x,
            minimum: 0,
            maximum: maximum,
            contentWidth: contentWidth
        )
    }

    private func setOffset(_ x: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        guard abs(clip.bounds.origin.x - x) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        scrollView.reflectScrolledClipView(clip)
    }
}
#else
private struct LiveSetlistZoomScrollAdjusterIOS: UIViewRepresentable {
    var batchID: Int?
    var delta: CGFloat

    func makeUIView(context: Context) -> LiveSetlistZoomScrollAdjusterIOSView {
        let view = LiveSetlistZoomScrollAdjusterIOSView()
        view.sync(batchID: batchID, delta: delta)
        return view
    }

    func updateUIView(_ uiView: LiveSetlistZoomScrollAdjusterIOSView, context: Context) {
        uiView.sync(batchID: batchID, delta: delta)
    }
}

private final class LiveSetlistZoomScrollAdjusterIOSView: UIView {
    private let driver = LiveSetlistZoomScrollDriver()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        driver.applyFromLayout(
            readMetrics: { self.scrollMetrics() },
            setOffset: { self.setOffset($0) }
        )
    }

    func sync(batchID: Int?, delta: CGFloat) {
        driver.sync(
            batchID: batchID,
            delta: delta,
            readMetrics: { [weak self] in self?.scrollMetrics() },
            setOffset: { [weak self] in self?.setOffset($0) }
        )
    }

    private func scrollMetrics() -> LiveSetlistZoomScrollMetrics? {
        guard let scrollView = enclosingScrollView() else { return nil }
        let minimum = -scrollView.adjustedContentInset.left
        let maximum = max(
            minimum,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )
        return LiveSetlistZoomScrollMetrics(
            offset: scrollView.contentOffset.x,
            minimum: minimum,
            maximum: maximum,
            contentWidth: scrollView.contentSize.width
        )
    }

    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    private func setOffset(_ x: CGFloat) {
        guard let scrollView = enclosingScrollView() else { return }
        guard abs(scrollView.contentOffset.x - x) > 0.5 else { return }
        scrollView.setContentOffset(CGPoint(x: x, y: scrollView.contentOffset.y), animated: false)
    }
}
#endif
