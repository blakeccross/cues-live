import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The song's in and out flags on the time ruler, like Logic's project end marker. Dragging a
/// flag moves that point and snaps it to the nearest beat. The ruler dims outside the range.
struct TimelinePlayRangeFlags: View {
    let playRange: SongPlayRange
    /// Where the content ends: the out point while it follows the song.
    let songEnd: TimeInterval
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let height: CGFloat
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    var preview: TimelinePlayRangePreview
    let onMove: (SongPlayRange) -> Void
    let onReset: () -> Void

    private static let dragSpace = "playRangeFlags"
    private static let flagWidth: CGFloat = 13
    private static let pennantHeight: CGFloat = 16
    private static let handleWidth: CGFloat = 18

    var body: some View {
        let shown = preview.range ?? playRange.resolved(songEnd: songEnd)
        let inX = xPosition(for: shown.lowerBound)
        let outX = xPosition(for: shown.upperBound)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Reset In and Out Points", action: onReset)
                        .disabled(playRange == SongPlayRange())
                }
            outsideWash(from: 0, to: inX)
            outsideWash(from: outX, to: displayWidth)
            TimelinePlayRangeEdgeShadow()
                .frame(width: TimelinePlayRangeEdgeShadow.width, height: height)
                .offset(x: outX)
            flag(.start, at: inX)
            flag(.end, at: outX)
        }
        .frame(width: displayWidth, height: height, alignment: .topLeading)
        .coordinateSpace(name: Self.dragSpace)
    }

    private func outsideWash(from start: CGFloat, to end: CGFloat) -> some View {
        Rectangle()
            .fill(AppColors.Timeline.outsidePlayRange)
            .frame(width: max(0, end - start), height: height)
            .offset(x: start)
            .allowsHitTesting(false)
    }

    /// Both pennants sit right of the point. The in flag's points away from it, into the range;
    /// the out flag's points back at it, like Logic's end marker. The pennant never leaves the
    /// ruler, even if that moves it off the point.
    private func flag(_ point: SongPlayRange.Point, at x: CGFloat) -> some View {
        let isIn = point == .start
        return ZStack(alignment: .topLeading) {
            PlayRangeFlagShape(pointsBack: !isIn, pennantHeight: min(Self.pennantHeight, height))
                .fill(AppColors.Timeline.playRangeFlag)
                .frame(width: Self.flagWidth, height: height)
                .offset(x: min(x, displayWidth - Self.flagWidth))
                .allowsHitTesting(false)
            Color.clear
                .frame(width: Self.handleWidth, height: height)
                .contentShape(Rectangle())
                .modifier(PlayRangeResizeCursor())
                .highPriorityGesture(dragGesture(for: point))
                .offset(x: x - Self.handleWidth / 3)
                .accessibilityElement()
                .accessibilityLabel(isIn ? "In point" : "Out point")
        }
    }

    private func dragGesture(for point: SongPlayRange.Point) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.dragSpace))
            .onChanged { value in
                preview.range = moved(point, toX: value.location.x).resolved(songEnd: songEnd)
            }
            .onEnded { value in
                let range = moved(point, toX: value.location.x)
                preview.range = nil
                onMove(range)
            }
    }

    private func moved(_ point: SongPlayRange.Point, toX x: CGFloat) -> SongPlayRange {
        let time = MeasureTiming.snapToNearestBeat(
            TimelineLayout.time(at: x, duration: duration, contentWidth: contentWidth),
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        return playRange.moving(point, to: time, songEnd: songEnd, limit: outPointLimit)
    }

    /// Latest out point whose pennant still fits on the ruler.
    private var outPointLimit: TimeInterval {
        let lastX = max(0, displayWidth - Self.flagWidth)
        return min(duration, TimelineLayout.time(at: lastX, duration: duration, contentWidth: contentWidth))
    }

    private func xPosition(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: duration, contentWidth: contentWidth)
    }
}

/// A triangular pennant at the top of the ruler, pointing right or back to the leading edge.
private struct PlayRangeFlagShape: Shape {
    let pointsBack: Bool
    let pennantHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let baseX = pointsBack ? rect.maxX : rect.minX
        let tipX = pointsBack ? rect.minX : rect.maxX
        var path = Path()
        path.move(to: CGPoint(x: baseX, y: rect.minY))
        path.addLine(to: CGPoint(x: tipX, y: rect.minY + pennantHeight / 2))
        path.addLine(to: CGPoint(x: baseX, y: rect.minY + pennantHeight))
        path.closeSubpath()
        return path
    }
}

/// Shows the left-right resize cursor over a flag.
private struct PlayRangeResizeCursor: ViewModifier {
    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.resizeLeftRight.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            #endif
    }
}
