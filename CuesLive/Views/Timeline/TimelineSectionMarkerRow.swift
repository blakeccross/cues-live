import SwiftUI
#if os(macOS)
import AppKit
#endif

struct TimelineSectionMarkerRowView: View {
    let sections: [ArrangementDisplaySection]
    let duration: TimeInterval
    let contentWidth: CGFloat
    let displayWidth: CGFloat
    let height: CGFloat
    let cuedSectionID: UUID?
    let cueFlashPhase: Bool
    let loopSlotIDs: Set<UUID>
    let isPlaying: Bool
    let onCueSection: (ArrangementDisplaySection) -> Void
    let onToggleLoopSection: (ArrangementDisplaySection) -> Void
    let onAddSection: (TimeInterval) -> Void
    let onAddSectionRange: (TimeInterval, TimeInterval) -> Void
    let snapSectionRange: (TimeInterval, TimeInterval) -> (TimeInterval, TimeInterval)
    let onRenameSection: (ArrangementDisplaySection) -> Void
    let onDeleteSection: (ArrangementDisplaySection) -> Void

    @State private var draftSectionRange: SectionDragDraft?

    private struct SectionDragDraft: Equatable {
        var start: TimeInterval
        var end: TimeInterval
    }

    private var safeDuration: TimeInterval {
        max(duration, 0.001)
    }

    /// Trailing boundary markers created only to end a dragged section have no name.
    /// They still set the previous section's end, and stay out of the colored row.
    private var visibleSections: [ArrangementDisplaySection] {
        sections.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: displayWidth, height: height)

            ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                TimelineSectionMarkerSegmentView(
                    section: section,
                    index: index,
                    duration: safeDuration,
                    contentWidth: contentWidth,
                    height: height,
                    isCued: cuedSectionID == section.id,
                    cueFlashPhase: cueFlashPhase,
                    isLoopSection: loopSlotIDs.contains(section.id),
                    isPlaying: isPlaying,
                    onCueSection: onCueSection,
                    onToggleLoopSection: onToggleLoopSection,
                    onAddSection: { time in onAddSection(time) },
                    onRenameSection: onRenameSection,
                    onDeleteSection: onDeleteSection
                )
            }

            if let draftSectionRange {
                let startX = TimelineLayout.xPosition(
                    for: draftSectionRange.start,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                let endX = TimelineLayout.xPosition(
                    for: draftSectionRange.end,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .overlay {
                        Rectangle()
                            .stroke(Color.accentColor, lineWidth: 1)
                    }
                    .frame(width: max(1, endX - startX), height: height)
                    .offset(x: startX)
                    .allowsHitTesting(false)
            }

            ForEach(sections) { section in
                let x = TimelineLayout.xPosition(
                    for: section.timelineStartSeconds,
                    duration: safeDuration,
                    contentWidth: contentWidth
                )
                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 1, height: height)
                    .offset(x: x)
            }
        }
        .frame(width: displayWidth, height: height)
        .contentShape(Rectangle())
        .highPriorityGesture(createSectionDrag)
        .onTapGesture(count: 2, coordinateSpace: .local) { location in
            let time = timelineTime(at: location.x)
            if isPlaying, let section = section(atTimeline: time) {
                onCueSection(section)
            } else if !isPlaying {
                onAddSection(time)
            }
        }
        #if os(macOS)
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }

    private var createSectionDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                draftSectionRange = sectionDragDraft(from: value.startLocation.x, to: value.location.x)
            }
            .onEnded { value in
                let draft = sectionDragDraft(from: value.startLocation.x, to: value.location.x)
                draftSectionRange = nil
                guard let draft else { return }
                onAddSectionRange(draft.start, draft.end)
            }
    }

    private func sectionDragDraft(from startX: CGFloat, to endX: CGFloat) -> SectionDragDraft? {
        let snapped = snapSectionRange(timelineTime(at: startX), timelineTime(at: endX))
        let start = min(max(0, snapped.0), safeDuration)
        let end = min(max(0, snapped.1), safeDuration)
        guard end - start >= SectionRangeInsertion.minimumDuration else { return nil }
        return SectionDragDraft(start: start, end: end)
    }

    private func timelineTime(at x: CGFloat) -> TimeInterval {
        let clampedX = min(max(0, x), contentWidth)
        return safeDuration * TimeInterval(clampedX / contentWidth)
    }

    private func section(atTimeline time: TimeInterval) -> ArrangementDisplaySection? {
        sections.first { $0.timelineStartSeconds <= time && time < $0.timelineEndSeconds }
    }
}

struct TimelineSectionMarkerSegmentView: View {
    let section: ArrangementDisplaySection
    let index: Int
    let duration: TimeInterval
    let contentWidth: CGFloat
    let height: CGFloat
    let isCued: Bool
    let cueFlashPhase: Bool
    let isLoopSection: Bool
    let isPlaying: Bool
    let onCueSection: (ArrangementDisplaySection) -> Void
    let onToggleLoopSection: (ArrangementDisplaySection) -> Void
    let onAddSection: (TimeInterval) -> Void
    let onRenameSection: (ArrangementDisplaySection) -> Void
    let onDeleteSection: (ArrangementDisplaySection) -> Void

    private var startX: CGFloat {
        TimelineLayout.xPosition(
            for: section.timelineStartSeconds,
            duration: duration,
            contentWidth: contentWidth
        )
    }

    private var segmentWidth: CGFloat {
        let endX = TimelineLayout.xPosition(
            for: section.timelineEndSeconds,
            duration: duration,
            contentWidth: contentWidth
        )
        return max(0, endX - startX)
    }

    private var sectionColor: Color {
        let colors: [Color] = [.blue, .purple, .teal, .indigo, .mint, .cyan]
        return colors[index % colors.count]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(sectionColor.opacity(isCued && cueFlashPhase ? 0.55 : 0.25))

            HStack(spacing: 2) {
                if isLoopSection {
                    Image(systemName: "repeat")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(sectionColor)
                }
                Text(section.name.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(sectionColor)
            }
            .padding(.horizontal, 4)
            .frame(width: segmentWidth, alignment: .leading)
        }
        .frame(width: segmentWidth, height: height)
        .overlay {
            if isCued {
                Rectangle()
                    .stroke(Color.yellow.opacity(cueFlashPhase ? 1 : 0.35), lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") {
                onRenameSection(section)
            }
            Button(isLoopSection ? "Remove Loop" : "Loop Section") {
                onToggleLoopSection(section)
            }
            if isPlaying {
                Button("Cue Section") {
                    onCueSection(section)
                }
            }
            Button("Delete Section", role: .destructive) {
                onDeleteSection(section)
            }
        }
        .onTapGesture(count: 2, coordinateSpace: .local) { location in
            if isPlaying {
                onCueSection(section)
            } else {
                let safeDuration = max(duration, 0.001)
                let clampedX = min(max(0, startX + location.x), contentWidth)
                let time = safeDuration * TimeInterval(clampedX / contentWidth)
                onAddSection(time)
            }
        }
        .offset(x: startX)
    }
}
