import SwiftData
import SwiftUI

enum LiveGroupMixerDetent: Equatable {
    case hidden
    case visible

    static let heightFraction: CGFloat = 0.48
    static let minimumMixerHeight: CGFloat = 140
    static let minimumMainHeight: CGFloat = 200

    /// Keeps the mixer at least its minimum height and leaves the setlist at least its own.
    static func clampedMixerHeight(_ height: CGFloat, totalHeight: CGFloat) -> CGFloat {
        let maximum = max(minimumMixerHeight, totalHeight - minimumMainHeight)
        return min(maximum, max(minimumMixerHeight, height))
    }
}

enum LivePlaybackSidebarMetrics {
    static let trailingAppStorageKey = "livePlaybackTrailingSidebarWidth"
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

    static func sidebarWidth(fromStorage value: Double, totalWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        clampedSidebarWidth(CGFloat(value), totalWidth: totalWidth)
    }

    static func storageValue(forWidth width: CGFloat, totalWidth: CGFloat = .greatestFiniteMagnitude) -> Double {
        Double(clampedSidebarWidth(width, totalWidth: totalWidth))
    }
}

struct LivePlaybackTrailingSidebarLayout<Sidebar: View, MainContent: View>: View {
    var isVisible: Bool
    /// Narrowest the pane may be dragged. Wider panes, like the song browser, raise it.
    var minimumWidth: CGFloat = LivePlaybackSidebarMetrics.minimumSidebarWidth
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let mainContent: () -> MainContent

    @AppStorage(LivePlaybackSidebarMetrics.trailingAppStorageKey)
    private var storedSidebarWidth = LivePlaybackSidebarMetrics.defaultSidebarWidthStorageValue

    @State private var sidebarWidth = LivePlaybackSidebarMetrics.defaultSidebarWidth
    @State private var totalWidth: CGFloat = .greatestFiniteMagnitude

    var body: some View {
        HStack(spacing: 0) {
            mainContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isVisible {
                AppResizableDivider(
                    length: $sidebarWidth,
                    edge: .leading,
                    clamp: { clampedWidth($0, totalWidth: totalWidth) },
                    accessibilityLabel: "Side panel width",
                    onResizeEnded: persistSidebarWidth
                )
                .zIndex(1)

                sidebar()
                    .frame(width: clampedWidth(sidebarWidth, totalWidth: totalWidth))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
            sidebarWidth = LivePlaybackSidebarMetrics.sidebarWidth(fromStorage: storedSidebarWidth)
        }
    }

    private func clampedWidth(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        LivePlaybackSidebarMetrics.clampedSidebarWidth(width, totalWidth: totalWidth, minimumWidth: minimumWidth)
    }

    private func persistSidebarWidth() {
        storedSidebarWidth = LivePlaybackSidebarMetrics.storageValue(
            forWidth: sidebarWidth,
            totalWidth: totalWidth
        )
    }
}

#if os(macOS)
/// Setlist above a resizable group mixer. A plain stack rather than a split view, so the
/// window's bottom safe area reaches whichever pane sits at the bottom.
struct LivePlaybackMixerSplitLayout<MainContent: View>: View {
    @Binding var mixerDetent: LiveGroupMixerDetent
    let onLiveVolumeChange: (UUID?, Double) -> Void
    let onMixChange: () -> Void
    @ViewBuilder let mainContent: () -> MainContent

    /// `nil` until the user resizes; the mixer then opens at a fraction of the height.
    @State private var mixerHeight: CGFloat?
    @State private var totalHeight: CGFloat = 0

    private var resolvedMixerHeight: CGFloat {
        LiveGroupMixerDetent.clampedMixerHeight(
            mixerHeight ?? totalHeight * LiveGroupMixerDetent.heightFraction,
            totalHeight: totalHeight
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            mainContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if mixerDetent == .visible {
                AppResizableDivider(
                    length: Binding(get: { resolvedMixerHeight }, set: { mixerHeight = $0 }),
                    edge: .top,
                    clamp: { LiveGroupMixerDetent.clampedMixerHeight($0, totalHeight: totalHeight) },
                    accessibilityLabel: "Group mixer height"
                )
                .zIndex(1)

                LiveGroupMixerPanel(
                    onLiveVolumeChange: onLiveVolumeChange,
                    onMixChange: onMixChange
                )
                .frame(height: resolvedMixerHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            totalHeight = height
        }
        .animation(AppAnimation.fadeQuick, value: mixerDetent)
    }
}

struct LiveGroupMixerPanel: View {
    let onLiveVolumeChange: (UUID?, Double) -> Void
    let onMixChange: () -> Void

    var body: some View {
        LiveGroupMixerView(
            onLiveVolumeChange: onLiveVolumeChange,
            onMixChange: onMixChange
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundSecondary)
    }
}
#endif

#if os(iOS)
struct LiveGroupMixerScreen: View {
    let onLiveVolumeChange: (UUID?, Double) -> Void
    let onMixChange: () -> Void

    var body: some View {
        LiveGroupMixerView(
            onLiveVolumeChange: onLiveVolumeChange,
            onMixChange: onMixChange
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground(.secondary)
        .navigationTitle("Group Mixer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .locksInterfaceOrientations(.landscape)
    }
}
#endif

struct LiveGroupMixerView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\TrackGroup.sortOrder), SortDescriptor(\TrackGroup.name)])
    private var groups: [TrackGroup]

    let onLiveVolumeChange: (UUID?, Double) -> Void
    let onMixChange: () -> Void

    @State private var routingConfig: OutputRoutingConfig?

    private let stripWidth: CGFloat = 96

    /// Timecode is routed as a dedicated LTC output and is not mixable.
    private var mixableGroups: [TrackGroup] {
        groups.filter { !TimecodePlaybackSupport.isTimecodeGroup($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            let stripHeight = geometry.size.height - AppSpacing.xs

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(mixableGroups) { group in
                        LiveGroupChannelStrip(
                            title: group.name,
                            titleColor: TrackGroupPalette.colors(for: group).body,
                            groupID: group.id,
                            volume: Binding(
                                get: { group.volume },
                                set: { group.volume = $0 }
                            ),
                            isMuted: Binding(
                                get: { group.isMuted },
                                set: { group.isMuted = $0 }
                            ),
                            stripHeight: stripHeight,
                            stripWidth: stripWidth,
                            onLiveVolumeChange: onLiveVolumeChange,
                            onMixChange: onMixChange
                        )
                    }

                    if let routingConfig {
                        LiveGroupChannelStrip(
                            title: "No Group",
                            titleColor: TrackGroupPalette.colors(forPaletteKey: nil).body,
                            groupID: nil,
                            volume: Binding(
                                get: { routingConfig.ungroupedVolume },
                                set: { routingConfig.ungroupedVolume = $0 }
                            ),
                            isMuted: Binding(
                                get: { routingConfig.ungroupedIsMuted },
                                set: { routingConfig.ungroupedIsMuted = $0 }
                            ),
                            stripHeight: stripHeight,
                            stripWidth: stripWidth,
                            onLiveVolumeChange: onLiveVolumeChange,
                            onMixChange: onMixChange
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.top, AppSpacing.xs)
            }
            .contentMargins(.bottom, 0, for: .scrollContent)
        }
        .background {
            GroupMeterRefreshTicker()
        }
        .onAppear {
            routingConfig = OutputRoutingStore.config(in: modelContext)
        }
    }
}

/// Owns the meter refresh timer so ticks don't invalidate the mixer layout.
private struct GroupMeterRefreshTicker: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
                AudioEngineManager.shared.refreshGroupMeters()
            }
    }
}

struct LiveGroupChannelStrip: View {
    let title: String
    let titleColor: Color
    let groupID: UUID?
    @Binding var volume: Double
    @Binding var isMuted: Bool
    let stripHeight: CGFloat
    var stripWidth: CGFloat = 96
    let onLiveVolumeChange: (UUID?, Double) -> Void
    let onMixChange: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppSpacing.xxs) {
                GeometryReader { geometry in
                    MixerFaderColumn(
                        value: $volume,
                        groupID: groupID,
                        height: max(60, geometry.size.height),
                        onLiveVolumeChange: { liveVolume in
                            onLiveVolumeChange(groupID, liveVolume)
                        },
                        onEditingEnded: onMixChange
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: 60, maxHeight: .infinity)

                TrackMixButton(
                    label: "M",
                    isActive: isMuted,
                    activeColor: .dawMuteActive
                ) {
                    isMuted.toggle()
                    onMixChange()
                }
            }
            .padding(.horizontal, AppSpacing.xxs)
            .padding(.top, AppSpacing.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .center)
                // Stays inside the label rather than running under the now-playing bar.
                .background(titleColor, ignoresSafeAreaEdges: [])
        }
        .frame(width: stripWidth, height: stripHeight, alignment: .bottom)
    }
}
