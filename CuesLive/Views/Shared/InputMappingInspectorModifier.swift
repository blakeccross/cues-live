import SwiftUI

#if os(iOS)
/// Presents `InputMappingPanel` as a system inspector while mapping: a trailing column in
/// regular width, a resizable sheet in compact width that leaves the setlist tappable.
@MainActor
struct InputMappingInspectorModifier: ViewModifier {
    @Environment(InputMappingController.self) private var mapping

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: isPresented) {
                InputMappingPanel()
                    .inspectorColumnWidth(
                        min: LivePlaybackSidebarMetrics.minimumSidebarWidth,
                        ideal: LivePlaybackSidebarMetrics.defaultSidebarWidth,
                        max: LivePlaybackSidebarMetrics.maximumSidebarWidth
                    )
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { mapping.isMapping },
            set: { isPresented in
                if !isPresented, mapping.isMapping {
                    mapping.endMapping()
                }
            }
        )
    }
}

extension View {
    func inputMappingInspector() -> some View {
        modifier(InputMappingInspectorModifier())
    }
}
#endif
