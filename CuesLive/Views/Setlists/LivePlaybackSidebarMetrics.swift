import CoreGraphics

/// Widths shared by the live window's side panes.
enum LivePlaybackSidebarMetrics {
    static let trailingAppStorageKey = "livePlaybackTrailingSidebarWidth"
    static let songBrowserAppStorageKey = "liveSongBrowserWidth"
    static let defaultSidebarWidth: CGFloat = 300
    static let defaultSidebarWidthStorageValue = Double(defaultSidebarWidth)
    static let minimumSidebarWidth: CGFloat = 240
    static let maximumSidebarWidth: CGFloat = 520
    static let minimumMainWidth: CGFloat = 280

    static func clampedSidebarWidth(
        _ width: CGFloat,
        totalWidth: CGFloat,
        minimumWidth: CGFloat = minimumSidebarWidth
    ) -> CGFloat {
        let availableMaximum = max(minimumWidth, totalWidth - minimumMainWidth)
        let cappedMaximum = min(maximumSidebarWidth, availableMaximum)
        return min(cappedMaximum, max(minimumWidth, width))
    }
}
