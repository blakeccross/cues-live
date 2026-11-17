import AVFoundation
import CoreGraphics
import Foundation

enum AudioTimelineMath {
    /// Converts a timeline offset (relative to trim start) to an absolute file frame index.
    static func frame(
        timelineOffset: TimeInterval,
        trimStart: TimeInterval,
        sampleRate: Double
    ) -> AVAudioFramePosition {
        AVAudioFramePosition(((trimStart + timelineOffset) * sampleRate).rounded(.toNearestOrAwayFromZero))
    }

    /// Snaps a timeline time to the nearest sample boundary.
    static func quantize(_ seconds: TimeInterval, sampleRate: Double) -> TimeInterval {
        guard sampleRate > 0 else { return seconds }
        return Double((seconds * sampleRate).rounded(.toNearestOrAwayFromZero)) / sampleRate
    }

    static func timelineOffset(
        fromFrame frame: AVAudioFramePosition,
        trimStart: TimeInterval,
        sampleRate: Double
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(frame) / sampleRate - trimStart
    }
}

enum TimelineLayout {
    static let basePixelsPerSecond: CGFloat = 6
    /// 96,000 pt a second: two points a sample at 48 kHz, a quarter of a sample per device
    /// pixel on a Retina display, as deep as SoundCraft goes. Past one sample a pixel the lanes
    /// draw a line through the samples. Layer and Core Graphics positions stay exact far beyond
    /// the widths this gives an hour-long song.
    static let maxZoom: CGFloat = 16_000
    static let minimumContentWidth: CGFloat = 320

    /// One step of a live zoom: the zoom, the width it maps the song to, and the offset that keeps
    /// the content at viewport x `anchorX` in place.
    struct LiveZoomStep: Equatable {
        let zoom: CGFloat
        let contentWidth: CGFloat
        let offset: CGFloat
    }

    /// The live zoom after multiplying `current` by `scale`, or `nil` when the range stops it.
    /// `committedWidth` is the width the editor's zoom, `committedZoom`, maps the song to.
    static func liveZoomStep(
        from current: CGFloat,
        by scale: CGFloat,
        range: ClosedRange<CGFloat>,
        committedZoom: CGFloat,
        committedWidth: CGFloat,
        offset: CGFloat,
        anchorX: CGFloat,
        viewportWidth: CGFloat
    ) -> LiveZoomStep? {
        guard committedZoom > 0, committedWidth > 0 else { return nil }
        let zoom = min(range.upperBound, max(range.lowerBound, current * scale))
        guard zoom != current else { return nil }
        let oldWidth = committedWidth * current / committedZoom
        let newWidth = committedWidth * zoom / committedZoom
        return LiveZoomStep(
            zoom: zoom,
            contentWidth: newWidth,
            offset: zoomedOffset(
                anchorX: anchorX,
                offset: offset,
                oldWidth: oldWidth,
                newWidth: newWidth,
                viewportWidth: viewportWidth
            )
        )
    }

    /// Scroll offset that keeps the content at viewport x `anchorX` in place when the content
    /// width changes from `oldWidth` to `newWidth`, clamped to the scrollable range.
    static func zoomedOffset(
        anchorX: CGFloat,
        offset: CGFloat,
        oldWidth: CGFloat,
        newWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        guard oldWidth > 0 else { return 0 }
        let fraction = (offset + anchorX) / oldWidth
        let target = fraction * newWidth - anchorX
        return min(max(0, target), max(0, newWidth - viewportWidth))
    }

    /// Most zoomed-out level: entire timeline fits in the visible viewport when possible.
    static func minZoom(duration: TimeInterval, viewportWidth: CGFloat) -> CGFloat {
        guard duration > 0, viewportWidth > 0 else { return 1 }
        let naturalWidth = CGFloat(max(duration, 1)) * basePixelsPerSecond
        let floorZoom = minimumContentWidth / naturalWidth
        let fitZoom = viewportWidth / naturalWidth
        if naturalWidth > viewportWidth {
            return max(floorZoom, fitZoom)
        }
        return max(floorZoom, 1)
    }

    /// Default lane height. Tracks can be resized between the micro and extreme presets.
    static let laneHeight: CGFloat = TrackLaneHeight.medium
    /// Shared by every lane so a rubber band can span tracks.
    static let trackLanesCoordinateSpace = "trackLanes"
    static let clipHeaderHeight: CGFloat = 16
    /// Width of the trim hit target on each end of a clip header.
    static let clipTrimHandleWidth: CGFloat = 14
    static let laneSpacing: CGFloat = 0
    static let laneDividerHeight: CGFloat = 1
    static let clipCornerRadius: CGFloat = 0
    static let clipLaneInset: CGFloat = 0
    static let clipSelectionBorderWidth: CGFloat = 2
    static let clipBorderWidth: CGFloat = 1
    static let sectionMarkerHeight: CGFloat = 22
    static let timeSignatureRulerHeight: CGFloat = 24
    static let tempoRulerHeight: CGFloat = 24
    /// Minutes-and-seconds ruler, the topmost row. It carries the song's in and out flags.
    static let rulerHeight: CGFloat = 22
    static let trackHeaderWidth: CGFloat = 204

    /// Time-signature, tempo, and section rulers, below the time ruler and above the tracks.
    static var topRulerHeight: CGFloat {
        sectionMarkerHeight + timeSignatureRulerHeight + tempoRulerHeight
    }

    static var rulerTotalHeight: CGFloat {
        topRulerHeight + rulerHeight
    }

    static func pixelsPerSecond(zoom: CGFloat) -> CGFloat {
        basePixelsPerSecond * zoom
    }

    static func contentWidth(for duration: TimeInterval, zoom: CGFloat = 1) -> CGFloat {
        max(minimumContentWidth, CGFloat(max(duration, 1)) * pixelsPerSecond(zoom: zoom))
    }

    static func xPosition(for time: TimeInterval, duration: TimeInterval, contentWidth: CGFloat) -> CGFloat {
        let safeDuration = max(duration, 0.001)
        return contentWidth * CGFloat(max(0, time) / safeDuration)
    }

    static func time(at x: CGFloat, duration: TimeInterval, contentWidth: CGFloat) -> TimeInterval {
        let safeDuration = max(duration, 0.001)
        guard contentWidth > 0 else { return 0 }
        let clampedX = min(max(0, x), contentWidth)
        return safeDuration * TimeInterval(clampedX / contentWidth)
    }
}

/// Lane heights, in points. Dragging a track's bottom edge snaps to a preset.
/// Holding Command sets any height between micro and extreme.
enum TrackLaneHeight {
    static let micro: CGFloat = 16
    static let mini: CGFloat = 24
    static let small: CGFloat = 46
    static let medium: CGFloat = 88
    static let large: CGFloat = 132
    static let jumbo: CGFloat = 220
    static let extreme: CGFloat = 440
    static let presets: [CGFloat] = [micro, mini, small, medium, large, jumbo, extreme]

    /// Stored on new tracks. Matches `medium`.
    static let storedDefault: Double = 88

    /// A saved height, or the default when the stored value is missing or out of range.
    static func resolved(_ stored: Double) -> CGFloat {
        guard stored.isFinite else { return medium }
        let points = CGFloat(stored).rounded()
        guard points >= micro, points <= extreme else { return medium }
        return points
    }

    /// Nearest preset. An equal distance keeps the shorter one.
    static func snapped(_ points: CGFloat) -> CGFloat {
        presets.min(by: { abs($0 - points) < abs($1 - points) }) ?? medium
    }

    /// Any height from micro to extreme, rounded to a point.
    static func free(_ points: CGFloat) -> CGFloat {
        min(max(points.rounded(), micro), extreme)
    }

    /// The next preset taller or shorter than `points`. The ends stay put.
    static func step(_ points: CGFloat, taller: Bool) -> CGFloat {
        let current = resolved(Double(points))
        if taller {
            return presets.first { $0 > current } ?? extreme
        }
        return presets.last { $0 < current } ?? micro
    }

    /// Tracks a height change applies to. Option reaches every shown track.
    /// Option-Shift reaches the selected tracks, and the dragged track is always included.
    static func targets(
        owned: some Sequence<UUID>,
        shown: [UUID],
        selected: Set<UUID>,
        option: Bool,
        shift: Bool
    ) -> [UUID] {
        let owned = Set(owned)
        return shown.filter { id in
            owned.contains(id) || (option && (shift ? selected.contains(id) : true))
        }
    }
}

/// Vertical placement of the edit lanes. Heights can differ per track.
struct TrackLaneFrames: Equatable {
    struct Row: Equatable {
        var height: CGFloat
        var originY: CGFloat
    }

    var rows: [Row]
    var totalHeight: CGFloat

    init(heights: [CGFloat], spacing: CGFloat = TimelineLayout.laneSpacing) {
        var rows: [Row] = []
        var y: CGFloat = 0
        for (index, height) in heights.enumerated() {
            rows.append(Row(height: height, originY: y))
            y += height
            if index < heights.count - 1 {
                y += spacing
            }
        }
        self.rows = rows
        self.totalHeight = heights.isEmpty ? 0 : y
    }

    func rowIndex(at y: CGFloat) -> Int {
        guard !rows.isEmpty else { return 0 }
        var index = 0
        for (candidate, row) in rows.enumerated() where y >= row.originY {
            index = candidate
        }
        return index
    }
}
