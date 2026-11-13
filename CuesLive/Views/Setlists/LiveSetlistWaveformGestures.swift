import SwiftUI

/// Tap seeks; drag is left to the enclosing scroll view for panning.
/// When arrangement sections are provided, a tap inside a section jumps to that
/// section (via `onSectionTap`) instead of the exact tap time — matching Mac.
struct WaveformSeekGestureModifier: ViewModifier {
    struct SectionHitTarget: Identifiable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval
    }

    let isEnabled: Bool
    let contentWidth: CGFloat
    let duration: TimeInterval
    var sections: [SectionHitTarget] = []
    var onSectionTap: ((UUID) -> Void)? = nil
    let onSeek: (TimeInterval) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            let time = TimelineLayout.time(
                                at: event.location.x,
                                duration: duration,
                                contentWidth: contentWidth
                            )
                            if let onSectionTap, let sectionID = sectionID(containing: time) {
                                onSectionTap(sectionID)
                            } else {
                                onSeek(time)
                            }
                        }
                )
        } else {
            content
        }
    }

    private func sectionID(containing time: TimeInterval) -> UUID? {
        guard !sections.isEmpty else { return nil }

        for section in sections {
            if time >= section.start && time < section.end {
                return section.id
            }
        }

        if let last = sections.last, time >= last.start && time <= last.end {
            return last.id
        }

        return nil
    }
}
