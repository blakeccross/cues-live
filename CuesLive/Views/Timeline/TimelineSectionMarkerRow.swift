import SwiftUI

/// Point markers on the section ruler. Each one is a right-pointing triangle at the
/// beat it starts. Right-click the row to add one.
struct TimelineSectionMarkerRowView: View {
    let sections: [SongSection]
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let height: CGFloat
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    let loopSectionIDs: Set<UUID>
    let isPlaying: Bool
    let onCueSection: (SongSection) -> Void
    let onToggleLoopSection: (SongSection) -> Void
    let onAddSection: (TimeInterval) -> Void
    let onRenameSection: (SongSection) -> Void
    let onRemoveMarker: (SongSection) -> Void
    let onDeleteSection: (SongSection) -> Void

    @State private var pointerX: CGFloat = 0
    @State private var markerFrames: [UUID: CGRect] = [:]

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(sections) { section in
                labelView(section)
            }
            ForEach(sections) { section in
                triangleView(section)
            }
        }
        .frame(width: displayWidth, height: height, alignment: .leading)
        .onPreferenceChange(SectionMarkerFramePreference.self) { markerFrames = $0 }
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .modifier(SectionMarkerPointerTracker(x: $pointerX))
                .contextMenu {
                    Button("Add Section Marker") {
                        onAddSection(timelineTime(at: pointerX))
                    }
                    if let section = section(at: pointerX) {
                        Button("Rename") {
                            onRenameSection(section)
                        }
                        Button(loopSectionIDs.contains(section.id) ? "Remove Loop" : "Loop Section") {
                            onToggleLoopSection(section)
                        }
                        if isPlaying {
                            Button("Cue Section") {
                                onCueSection(section)
                            }
                        }
                        Divider()
                        Button("Remove Marker") {
                            onRemoveMarker(section)
                        }
                        Button("Delete Section and Audio", role: .destructive) {
                            onDeleteSection(section)
                        }
                    }
                }
        }
    }

    private func triangleView(_ section: SongSection) -> some View {
        let origin = markerOrigin(section)
        return SectionMarkerTriangle()
            .fill(markerColor(for: section))
            .frame(width: origin.triangleWidth, height: origin.side)
            .frame(height: height, alignment: .center)
            .preference(
                key: SectionMarkerFramePreference.self,
                value: [section.id: CGRect(x: origin.x, y: 0, width: origin.triangleWidth, height: height)]
            )
            .offset(x: origin.x)
            .allowsHitTesting(false)
    }

    /// The name sits after its triangle and is cut off where the next marker starts.
    @ViewBuilder
    private func labelView(_ section: SongSection) -> some View {
        let origin = markerOrigin(section)
        let name = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsLoop = loopSectionIDs.contains(section.id)
        let room = textLimit(after: section, labelX: origin.labelX)
        if room > 0.5, showsLoop || !name.isEmpty {
            labelChip(section, origin: origin, name: name, showsLoop: showsLoop, room: room)
        }
    }

    private func labelChip(
        _ section: SongSection,
        origin: (x: CGFloat, side: CGFloat, triangleWidth: CGFloat, labelX: CGFloat),
        name: String,
        showsLoop: Bool,
        room: CGFloat
    ) -> some View {
        let chip = HStack(spacing: 3) {
            if showsLoop {
                Image(systemName: "repeat")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
            }
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: height, alignment: .leading)
        .background(Color.dawStickyRulerBackground)
        .background {
            GeometryReader { geometry in
                let visible = min(geometry.size.width, room)
                Color.clear.preference(
                    key: SectionMarkerFramePreference.self,
                    value: [section.id: CGRect(
                        x: origin.x,
                        y: 0,
                        width: origin.labelX - origin.x + visible,
                        height: height
                    )]
                )
            }
        }

        // The name keeps its full width so it isn't truncated with an ellipsis.
        // The clear frame is the clip rect: a max-width frame grows to that full
        // width, and the text then draws past the next marker.
        return Color.clear
            .frame(width: room, height: height)
            .overlay(alignment: .leading) { chip }
            .clipped()
            .offset(x: origin.labelX)
            .allowsHitTesting(false)
    }

    private func markerOrigin(_ section: SongSection) -> (x: CGFloat, side: CGFloat, triangleWidth: CGFloat, labelX: CGFloat) {
        let x = TimelineLayout.xPosition(
            for: section.timelineStartSeconds,
            duration: safeDuration,
            contentWidth: contentWidth
        )
        let side = height - 6
        let triangleWidth = side * Self.triangleAltitude
        return (x, side, triangleWidth, x + triangleWidth + 4)
    }

    /// Room for this name: from the end of its triangle up to the next marker.
    /// The next marker counts even when it starts inside this triangle, so a long
    /// name is cut off at that marker instead of running out past it.
    private func textLimit(after section: SongSection, labelX: CGFloat) -> CGFloat {
        let sectionX = markerOrigin(section).x
        let nextX = sections
            .map { markerOrigin($0).x }
            .filter { $0 > sectionX + 0.5 }
            .min() ?? max(displayWidth, contentWidth)
        return max(0, nextX - labelX)
    }

    /// A cued marker pulses between the gray and a dimmer gray.
    private func markerColor(for section: SongSection) -> Color {
        let gray = AppColors.textTertiary
        guard cuedSectionID == section.id else { return gray }
        return cueFlashPhase ? gray : gray.opacity(0.35)
    }

    /// The marker whose triangle or name is under `x`. Later markers win when they overlap.
    private func section(at x: CGFloat) -> SongSection? {
        let point = CGPoint(x: x, y: height / 2)
        return sections.reversed().first { section in
            guard let frame = markerFrames[section.id] else { return false }
            return frame.insetBy(dx: -4, dy: 0).contains(point)
        }
    }

    private func timelineTime(at x: CGFloat) -> TimeInterval {
        let clampedX = min(max(0, x), contentWidth)
        return safeDuration * TimeInterval(clampedX / contentWidth)
    }

    /// Altitude of an equilateral triangle, as a fraction of its side.
    private static let triangleAltitude = CGFloat(3).squareRoot() / 2
}

/// An equilateral triangle. The vertical side is the marker time and the point faces right.
private struct SectionMarkerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SectionMarkerFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        for (id, rect) in nextValue() {
            guard let existing = value[id] else {
                value[id] = rect
                continue
            }
            let minX = min(existing.minX, rect.minX)
            let maxX = max(existing.maxX, rect.maxX)
            value[id] = CGRect(x: minX, y: 0, width: maxX - minX, height: max(existing.height, rect.height))
        }
    }
}

/// Records the pointer so Add Section Marker uses the time under the click.
private struct SectionMarkerPointerTracker: ViewModifier {
    @Binding var x: CGFloat

    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    x = location.x
                }
            }
            #else
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        x = value.startLocation.x
                    }
            )
            #endif
    }
}
