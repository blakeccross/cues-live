import CoreGraphics
import Foundation

/// Where a clip's fade handles sit, in the clip's own coordinates with the header at the top.
///
/// Each end has a length handle at the unity end of its fade, on the top of the clip body; with
/// no fade that is the body's top corner. A fade wide enough also has a curve handle on the
/// middle of its curve.
struct ClipFadeLayout {
    static let handleSize: CGFloat = 16
    /// Narrower clips have no handles, so the whole clip stays free to select and move.
    static let minimumClipWidth: CGFloat = 40
    static let minimumBodyHeight: CGFloat = 24
    /// A fade narrower than this has no curve handle.
    static let minimumCurveWidth: CGFloat = 32

    let clip: TrackClip
    let clipWidth: CGFloat
    let clipHeight: CGFloat

    var bodyTop: CGFloat { TimelineLayout.clipHeaderHeight }
    var bodyHeight: CGFloat { max(0, clipHeight - bodyTop) }

    var showsHandles: Bool {
        clip.duration > 0 && clipWidth >= Self.minimumClipWidth && bodyHeight >= Self.minimumBodyHeight
    }

    func fade(at edge: ClipEditing.Edge) -> ClipFade {
        edge == .leading ? clip.fadeIn : clip.fadeOut
    }

    func time(atX x: CGFloat) -> TimeInterval {
        guard clipWidth > 0 else { return clip.timelineStartSeconds }
        return clip.timelineStartSeconds + Double(x / clipWidth) * clip.duration
    }

    /// Centre of the length handle, kept whole inside the clip.
    func lengthHandle(at edge: ClipEditing.Edge) -> CGPoint {
        let half = Self.handleSize / 2
        let headX = edge == .leading ? fadeWidth(at: edge) : clipWidth - fadeWidth(at: edge)
        return CGPoint(x: min(max(headX, half), clipWidth - half), y: bodyTop + half)
    }

    /// Centre of the curve handle, on the middle of the fade's curve.
    func curveHandle(at edge: ClipEditing.Edge) -> CGPoint? {
        let width = fadeWidth(at: edge)
        guard width >= Self.minimumCurveWidth else { return nil }
        let inset = min(bodyHeight, Self.handleSize) / 4
        let y = bodyTop + bodyHeight * CGFloat(1 - fade(at: edge).gain(at: 0.5))
        return CGPoint(
            x: edge == .leading ? width / 2 : clipWidth - width / 2,
            y: min(max(y, bodyTop + inset), bodyTop + bodyHeight - inset)
        )
    }

    /// The fade cursor for a pointer over one of the handles.
    func cursor(at location: CGPoint) -> ClipPointerCursor? {
        guard showsHandles else { return nil }
        let half = Self.handleSize / 2
        func covers(_ handle: CGPoint) -> Bool {
            abs(location.x - handle.x) <= half && abs(location.y - handle.y) <= half
        }
        for edge in [ClipEditing.Edge.leading, .trailing] {
            if covers(lengthHandle(at: edge)) { return .fadeLength }
            if let handle = curveHandle(at: edge), covers(handle) { return .fadeCurve }
        }
        return nil
    }

    private func fadeWidth(at edge: ClipEditing.Edge) -> CGFloat {
        guard clip.duration > 0 else { return 0 }
        return clipWidth * CGFloat(fade(at: edge).duration / clip.duration)
    }
}
