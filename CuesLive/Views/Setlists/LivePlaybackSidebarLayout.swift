import SwiftUI

/// Main content beside a resizable side pane on either edge. The pane's width persists
/// under `widthStorageKey`, so panes on different edges keep their own widths.
struct LivePlaybackSidebarLayout<Sidebar: View, MainContent: View>: View {
    let edge: HorizontalEdge
    let isVisible: Bool
    /// Narrowest the pane may be dragged. Wider panes, like the song browser, raise it.
    let minimumWidth: CGFloat
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let mainContent: () -> MainContent

    @AppStorage private var storedSidebarWidth: Double

    @State private var sidebarWidth = LivePlaybackSidebarMetrics.defaultSidebarWidth
    @State private var totalWidth: CGFloat = .greatestFiniteMagnitude

    init(
        edge: HorizontalEdge = .trailing,
        isVisible: Bool,
        minimumWidth: CGFloat = LivePlaybackSidebarMetrics.minimumSidebarWidth,
        widthStorageKey: String = LivePlaybackSidebarMetrics.trailingAppStorageKey,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder mainContent: @escaping () -> MainContent
    ) {
        self.edge = edge
        self.isVisible = isVisible
        self.minimumWidth = minimumWidth
        self.sidebar = sidebar
        self.mainContent = mainContent
        _storedSidebarWidth = AppStorage(
            wrappedValue: LivePlaybackSidebarMetrics.defaultSidebarWidthStorageValue,
            widthStorageKey
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if edge == .leading, isVisible {
                pane
                divider
            }

            mainContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if edge == .trailing, isVisible {
                divider
                pane
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            totalWidth = newWidth
            let clamped = clampedWidth(sidebarWidth, totalWidth: newWidth)
            guard clamped != sidebarWidth else { return }
            sidebarWidth = clamped
            persistSidebarWidth()
        }
        .animation(AppAnimation.springSmooth, value: isVisible)
        .animation(.none, value: sidebarWidth)
        .onAppear {
            sidebarWidth = clampedWidth(CGFloat(storedSidebarWidth), totalWidth: totalWidth)
        }
    }

    private var pane: some View {
        sidebar()
            .frame(width: clampedWidth(sidebarWidth, totalWidth: totalWidth))
            .transition(.move(edge: edge == .leading ? .leading : .trailing).combined(with: .opacity))
    }

    private var divider: some View {
        AppResizableDivider(
            length: $sidebarWidth,
            edge: edge == .leading ? .trailing : .leading,
            clamp: { clampedWidth($0, totalWidth: totalWidth) },
            accessibilityLabel: "Side panel width",
            onResizeEnded: persistSidebarWidth
        )
        .zIndex(1)
    }

    private func clampedWidth(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        LivePlaybackSidebarMetrics.clampedSidebarWidth(width, totalWidth: totalWidth, minimumWidth: minimumWidth)
    }

    private func persistSidebarWidth() {
        storedSidebarWidth = Double(clampedWidth(sidebarWidth, totalWidth: totalWidth))
    }
}
