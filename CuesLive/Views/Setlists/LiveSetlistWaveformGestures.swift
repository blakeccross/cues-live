import SwiftUI
#if os(iOS)
import UIKit
#endif

/// View-aligned snapping while free-scrolling; no-op while following the playhead.
/// Implemented as `ScrollTargetBehavior` (not a conditional `ViewModifier`) so
/// enabling/disabling follow does not change ScrollView identity or reset offset.
struct LiveSetlistFollowScrollTargetBehavior: ScrollTargetBehavior {
    var isFollowing: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard !isFollowing else { return }
        ViewAlignedScrollTargetBehavior().updateTarget(&target, context: context)
    }
}

struct LiveSetlistFollowScrollDriver: View {
    let date: Date
    let action: () -> Void

    var body: some View {
        Color.clear
            .onAppear(perform: action)
            .onChange(of: date) { _, _ in
                action()
            }
    }
}

struct LiveSetlistFollowUserScrollDetector: ViewModifier {
    @Binding var isFollowing: Bool
    @Binding var isUserScrolling: Bool
    /// Programmatic playhead-anchored zoom also moves the scroll view.
    var suspendsUserScrollTracking = false

    func body(content: Content) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, newPhase in
                    guard !suspendsUserScrollTracking else { return }
                    switch newPhase {
                    case .interacting, .decelerating:
                        isUserScrolling = true
                        isFollowing = false
                    default:
                        isUserScrolling = false
                    }
                }
        } else {
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { _ in
                            guard !suspendsUserScrollTracking else { return }
                            isUserScrolling = true
                            isFollowing = false
                        }
                        .onEnded { _ in
                            guard !suspendsUserScrollTracking else { return }
                            isUserScrolling = false
                        }
                )
        }
    }
}

struct LiveSetlistPlayheadViewportXKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Tap seeks; drag is left to the parent horizontal ScrollView for panning.
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

#if os(iOS)
/// Pinch-to-zoom on the live waveform for touch screens. A SwiftUI pinch attached around the
/// horizontal ScrollView loses two-finger touches to the scroll view's own pan recognizer, so on
/// iOS 18+ a UIKit pinch recognizer runs alongside scrolling instead. iOS 17 keeps the SwiftUI
/// gesture.
struct LiveSetlistTouchPinchModifier<Fallback: Gesture>: ViewModifier {
    let fallbackGesture: Fallback
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(LiveSetlistPinchRecognizer(onChanged: onChanged, onEnded: onEnded))
        } else {
            content.simultaneousGesture(fallbackGesture)
        }
    }
}

@available(iOS 18.0, *)
private struct LiveSetlistPinchRecognizer: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.scale)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Let pinch run alongside the scroll view's pan and the lanes' tap and drag gestures.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif
