import CoreGraphics
import Foundation

/// Horizontal scroll state of the setlist waveform strip.
///
/// The scroll host reports where each song lane sits, how wide the strip is and when the user
/// scrolls it; the model decides where the strip should be. While following, the playhead stays
/// centered. After a zoom, the content under the playhead stays put. When the song changes while
/// not following, the new song's lane moves to the leading edge.
///
/// Nothing here is observed by SwiftUI, so a scroll tick or a playhead move rebuilds nothing.
/// The host and the lane canvas read it on each display-link frame.
@MainActor
final class LiveSetlistScrollModel {
    /// A song lane's waveform, in strip coordinates.
    struct Lane: Equatable, Sendable {
        var frame: CGRect
        var duration: TimeInterval
    }

    private(set) var offset: CGFloat = 0
    private(set) var contentWidth: CGFloat = 0
    private(set) var isFollowing = true
    private(set) var isUserScrolling = false
    private(set) var playheadTime: TimeInterval = 0

    /// Live playhead source while playing.
    var currentTime: () -> TimeInterval = { 0 }
    var isPlaying: () -> Bool = { false }
    /// Playhead while stopped. `nil` means the owner considers playback running.
    var idleTime: TimeInterval?
    /// Called when the strip's layout changes, so the host can resize and reposition.
    var onLayoutChange: () -> Void = {}

    private var lanes: [Int: Lane] = [:]
    private var currentIndex = 0
    private var viewportWidth: CGFloat = 0
    /// Content time that stays at a fixed viewport x through a zoom.
    private var anchor: (time: TimeInterval, viewportX: CGFloat)?
    private var revealsCurrentLane = false

    /// True while the playhead can move without the owner re-rendering, so the host's clock
    /// must keep running.
    var needsClock: Bool {
        idleTime == nil || isPlaying()
    }

    // MARK: - Layout reports

    func setLane(_ lane: Lane?, at index: Int) {
        guard lanes[index] != lane else { return }
        lanes[index] = lane
        onLayoutChange()
    }

    /// Drops lanes for songs no longer in the strip. Lanes are not cleared when their view
    /// disappears: SwiftUI can remove an old copy of a lane after the new one has reported.
    func retainLanes(at indices: Set<Int>) {
        let stale = lanes.keys.filter { !indices.contains($0) }
        guard !stale.isEmpty else { return }
        for index in stale {
            lanes[index] = nil
        }
        onLayoutChange()
    }

    func setContentWidth(_ width: CGFloat) {
        guard abs(contentWidth - width) > 0.25 else { return }
        contentWidth = width
        onLayoutChange()
    }

    func setViewportWidth(_ width: CGFloat) {
        guard abs(viewportWidth - width) > 0.5 else { return }
        viewportWidth = max(0, width)
    }

    func setCurrentIndex(_ index: Int) {
        guard index != currentIndex else { return }
        currentIndex = index
        anchor = nil
        revealsCurrentLane = !isFollowing
    }

    // MARK: - Scrolling

    /// The host moved the strip. `byUser` is false for moves the model asked for and for
    /// clamping after a resize.
    func didScroll(to newOffset: CGFloat, byUser: Bool) {
        offset = newOffset
        if byUser {
            isFollowing = false
            anchor = nil
            revealsCurrentLane = false
        }
    }

    func beginUserScroll() {
        isUserScrolling = true
    }

    func endUserScroll() {
        isUserScrolling = false
        relatchIfCentered()
    }

    /// Keeps the content under the playhead where it is through the zoom that follows.
    /// Following needs no anchor: it re-centers the playhead at the new zoom.
    func anchorPlayheadForZoom() {
        guard !isFollowing, let x = contentX(at: playheadTime) else { return }
        anchor = (playheadTime, x - offset)
    }

    /// Reads the playhead from the live source, or the idle time while stopped.
    func refreshPlayhead() {
        let time = idleTime.flatMap { isPlaying() ? nil : $0 } ?? currentTime()
        setPlayheadTime(time)
    }

    func setPlayheadTime(_ time: TimeInterval) {
        playheadTime = time
        relatchIfCentered()
    }

    /// Offset the strip should move to now, or `nil` to leave it where it is.
    func targetOffset() -> CGFloat? {
        guard !isUserScrolling else { return nil }
        let target: CGFloat
        if isFollowing {
            guard let x = contentX(at: playheadTime) else { return nil }
            target = x - viewportWidth / 2
        } else if let anchor, let x = contentX(at: anchor.time) {
            target = x - anchor.viewportX
        } else if revealsCurrentLane, let lane = lanes[currentIndex] {
            target = lane.frame.minX
        } else {
            return nil
        }
        let clamped = min(max(0, target), max(0, contentWidth - viewportWidth))
        return abs(clamped - offset) > 0.25 ? clamped : nil
    }

    /// Where the song at `index` sits in the strip, once it has reported.
    func lane(at index: Int) -> Lane? {
        lanes[index]
    }

    /// Strip x of the playhead, or `nil` while the current song has no lane.
    var playheadX: CGFloat? {
        contentX(at: playheadTime)
    }

    /// The playhead line in strip coordinates, or `nil` while the current song has no lane.
    func playheadFrame(width: CGFloat) -> CGRect? {
        guard let lane = lanes[currentIndex], let x = contentX(at: playheadTime) else { return nil }
        return CGRect(x: x - width / 2, y: lane.frame.minY, width: width, height: lane.frame.height)
    }

    // MARK: - Private

    private func contentX(at time: TimeInterval) -> CGFloat? {
        guard let lane = lanes[currentIndex] else { return nil }
        let clampedTime = min(max(0, time), max(lane.duration, 0.001))
        return lane.frame.minX + TimelineLayout.xPosition(
            for: clampedTime,
            duration: lane.duration,
            contentWidth: lane.frame.width
        )
    }

    /// Follows again once the playhead drifts, or is scrolled, back to the viewport center.
    private func relatchIfCentered() {
        guard !isFollowing, !isUserScrolling, viewportWidth > 0,
              let x = contentX(at: playheadTime) else { return }
        guard abs(x - offset - viewportWidth / 2) <= LiveSetlistWaveformMetrics.followRelatchDistance else {
            return
        }
        isFollowing = true
        anchor = nil
        revealsCurrentLane = false
    }
}
