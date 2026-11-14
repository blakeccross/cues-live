import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Sections on the marker ruler, drawn as square-cornered blocks. Click a block to select it.
/// Dragging an edge of the selected block moves only that edge; dragging the boundary between two
/// unselected blocks moves both. Right-click the row to add, rename, loop, or remove a marker.
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
    /// Sections as they would be after an edge edit, drawn while the edge is dragged.
    let previewSections: (SectionEdgeEdit) -> [SongSection]
    let onEditSectionEdge: (SectionEdgeEdit) -> Void
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]

    @State private var pointerX: CGFloat = 0
    @State private var selectedSectionID: UUID?
    @State private var pendingEdit: SectionEdgeEdit?

    private static let dragSpace = "sectionMarkerRow"
    private static let blockInset: CGFloat = 2
    private static let handleWidth: CGFloat = 8

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    var body: some View {
        let shown = pendingEdit.map(previewSections) ?? sections
        ZStack(alignment: .topLeading) {
            ForEach(shown) { section in
                blockView(section)
            }
        }
        .frame(width: displayWidth, height: height, alignment: .topLeading)
        .background(AppColors.Timeline.stickyRulerBackground)
        .overlay { interactionSurface(sections: shown) }
        .overlay(alignment: .topLeading) {
            ForEach(SectionEdge.edges(of: sections)) { edge in
                edgeHandle(edge)
            }
        }
        .coordinateSpace(name: Self.dragSpace)
    }

    private func blockView(_ section: SongSection) -> some View {
        let startX = xPosition(for: section.timelineStartSeconds)
        // One point wider so neighbouring blocks share a single border line.
        let width = max(0, xPosition(for: section.timelineEndSeconds) - startX) + 1
        let blockHeight = max(0, height - Self.blockInset * 2)
        let isSelected = selectedSectionID == section.id
        return Rectangle()
            .fill(fillColor(for: section, isSelected: isSelected))
            .overlay { Rectangle().strokeBorder(AppColors.paneDivider, lineWidth: 1) }
            .overlay(alignment: .leading) { blockLabel(section, isSelected: isSelected) }
            .frame(width: width, height: blockHeight)
            .clipped()
            .offset(x: startX, y: Self.blockInset)
            .allowsHitTesting(false)
    }

    private func blockLabel(_ section: SongSection, isSelected: Bool) -> some View {
        let name = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: AppSpacing.tagGlyphGap) {
            if loopSectionIDs.contains(section.id) {
                Image(systemName: "repeat")
                    .font(AppTypography.Compact.glyphEmphasized)
            }
            if !name.isEmpty {
                Text(name)
                    .font(AppTypography.Compact.sectionName)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(isSelected ? AppColors.backgroundSecondary : AppColors.textPrimary)
        .padding(.horizontal, AppSpacing.tagInsets.leading)
    }

    /// A cued block pulses between its fill and a dimmer version of it.
    private func fillColor(for section: SongSection, isSelected: Bool) -> Color {
        let fill = isSelected ? AppColors.sectionMarkerSelected : AppColors.sectionMarker
        guard cuedSectionID == section.id else { return fill }
        return cueFlashPhase ? fill : fill.opacity(0.45)
    }

    private func edgeHandle(_ edge: SectionEdge) -> some View {
        Color.clear
            .frame(width: Self.handleWidth, height: height)
            .contentShape(Rectangle())
            .modifier(ResizeCursorModifier())
            .highPriorityGesture(dragGesture(for: edge))
            .offset(x: xPosition(for: edge.time) - Self.handleWidth / 2)
            .accessibilityLabel(edge.accessibilityLabel)
    }

    private func dragGesture(for edge: SectionEdge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.dragSpace))
            .onChanged { value in
                pendingEdit = edit(for: edge, atX: value.location.x)
            }
            .onEnded { value in
                let edit = edit(for: edge, atX: value.location.x)
                pendingEdit = nil
                onEditSectionEdge(edit)
            }
    }

    /// The selected block's edge moves on its own. A shared boundary between two unselected blocks
    /// moves the marker and the previous block's end together.
    private func edit(for edge: SectionEdge, atX x: CGFloat) -> SectionEdgeEdit {
        let time = MeasureTiming.snapToNearestBeat(
            timelineTime(at: x),
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        switch edge.kind {
        case .end:
            return .end(sectionID: edge.sectionID, time: time)
        case .start(let previousID):
            if let previousID, selectedSectionID == previousID {
                return .end(sectionID: previousID, time: time)
            }
            let independent = previousID == nil || selectedSectionID == edge.sectionID
            return .start(sectionID: edge.sectionID, time: time, independent: independent)
        }
    }

    private func interactionSurface(sections shown: [SongSection]) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .modifier(SectionMarkerPointerTracker(x: $pointerX))
            .gesture(
                SpatialTapGesture()
                    .onEnded { event in
                        selectedSectionID = shown.section(atTimeline: timelineTime(at: event.location.x))?.id
                    }
            )
            .contextMenu {
                Button("Add Section Marker") {
                    onAddSection(timelineTime(at: pointerX))
                }
                if let section = shown.section(atTimeline: timelineTime(at: pointerX)) {
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
                }
            }
    }

    private func xPosition(for time: TimeInterval) -> CGFloat {
        TimelineLayout.xPosition(for: time, duration: safeDuration, contentWidth: contentWidth)
    }

    private func timelineTime(at x: CGFloat) -> TimeInterval {
        let clampedX = min(max(0, x), contentWidth)
        return safeDuration * TimeInterval(clampedX / contentWidth)
    }
}

/// A draggable block edge. Where one block ends exactly where the next starts, the two share a
/// single start edge that remembers the block before it.
private struct SectionEdge: Identifiable {
    enum Kind {
        case start(previousID: UUID?)
        case end
    }

    let sectionID: UUID
    let name: String
    let time: TimeInterval
    let kind: Kind

    var id: String {
        switch kind {
        case .start: "start-\(sectionID)"
        case .end: "end-\(sectionID)"
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .start: "\(name) start"
        case .end: "\(name) end"
        }
    }

    static func edges(of sections: [SongSection]) -> [SectionEdge] {
        sections.enumerated().flatMap { index, section -> [SectionEdge] in
            let previous = index > 0 ? sections[index - 1] : nil
            let next = index + 1 < sections.count ? sections[index + 1] : nil
            let previousID = previous.flatMap { meets($0, section) ? $0.id : nil }
            var edges = [SectionEdge(
                sectionID: section.id,
                name: section.name,
                time: section.timelineStartSeconds,
                kind: .start(previousID: previousID)
            )]
            if next.map({ !meets(section, $0) }) ?? true {
                edges.append(SectionEdge(
                    sectionID: section.id,
                    name: section.name,
                    time: section.timelineEndSeconds,
                    kind: .end
                ))
            }
            return edges
        }
    }

    private static func meets(_ earlier: SongSection, _ later: SongSection) -> Bool {
        abs(earlier.timelineEndSeconds - later.timelineStartSeconds) < 0.000_5
    }
}

/// Shows the left-right resize cursor over a block edge.
private struct ResizeCursorModifier: ViewModifier {
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
