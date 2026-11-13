import SwiftData
import SwiftUI

enum LiveGroupMixerDetent: Equatable {
    case hidden
    case visible

    static let heightFraction: CGFloat = 0.48
    static let minimumMixerHeight: CGFloat = 140
    static let minimumMainHeight: CGFloat = 200
}

enum LivePlaybackSidebarMetrics {
    static let trailingAppStorageKey = "livePlaybackTrailingSidebarWidth"
    static let defaultSidebarWidth: CGFloat = 300
    static let defaultSidebarWidthStorageValue = Double(defaultSidebarWidth)
    static let minimumSidebarWidth: CGFloat = 240
    static let maximumSidebarWidth: CGFloat = 520
    static let minimumMainWidth: CGFloat = 280
    static let resizeHitAreaWidth: CGFloat = 10
    private static let resizeAdjustmentStep: CGFloat = 16

    static func clampedSidebarWidth(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let availableMaximum = max(minimumSidebarWidth, totalWidth - minimumMainWidth)
        let cappedMaximum = min(maximumSidebarWidth, availableMaximum)
        return min(cappedMaximum, max(minimumSidebarWidth, width))
    }

    static func sidebarWidth(fromStorage value: Double, totalWidth: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        clampedSidebarWidth(CGFloat(value), totalWidth: totalWidth)
    }

    static func storageValue(forWidth width: CGFloat, totalWidth: CGFloat = .greatestFiniteMagnitude) -> Double {
        Double(clampedSidebarWidth(width, totalWidth: totalWidth))
    }

    static func adjustedSidebarWidth(_ width: CGFloat, direction: AccessibilityAdjustmentDirection, totalWidth: CGFloat) -> CGFloat {
        let delta: CGFloat
        switch direction {
        case .increment:
            delta = resizeAdjustmentStep
        case .decrement:
            delta = -resizeAdjustmentStep
        @unknown default:
            delta = 0
        }
        return clampedSidebarWidth(width + delta, totalWidth: totalWidth)
    }
}

/// Drag handle on the leading edge of a trailing sidebar; dragging left widens it.
private struct LivePlaybackSidebarResizeHandle: View {
    @Binding var width: CGFloat
    let totalWidth: CGFloat
    let accessibilityLabel: String
    let onResizeEnded: () -> Void

    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: LivePlaybackSidebarMetrics.resizeHitAreaWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }
                    let proposed = (dragStartWidth ?? width) - value.translation.width
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        width = LivePlaybackSidebarMetrics.clampedSidebarWidth(proposed, totalWidth: totalWidth)
                    }
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    onResizeEnded()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int(LivePlaybackSidebarMetrics.clampedSidebarWidth(width, totalWidth: totalWidth))) points")
        .accessibilityAdjustableAction { direction in
            width = LivePlaybackSidebarMetrics.adjustedSidebarWidth(width, direction: direction, totalWidth: totalWidth)
            onResizeEnded()
        }
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.resizeLeftRight.push()
            case .ended:
                NSCursor.pop()
            }
        }
        #endif
    }
}

struct LivePlaybackTrailingSidebarLayout<Sidebar: View, MainContent: View>: View {
    var isVisible: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let mainContent: () -> MainContent

    @AppStorage(LivePlaybackSidebarMetrics.trailingAppStorageKey)
    private var storedSidebarWidth = LivePlaybackSidebarMetrics.defaultSidebarWidthStorageValue

    @State private var sidebarWidth = LivePlaybackSidebarMetrics.defaultSidebarWidth

    var body: some View {
        GeometryReader { geometry in
            let clampedWidth = LivePlaybackSidebarMetrics.clampedSidebarWidth(
                sidebarWidth,
                totalWidth: geometry.size.width
            )

            HStack(spacing: 0) {
                mainContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isVisible {
                    Rectangle()
                        .fill(AppColors.separator)
                        .frame(width: 0.5)

                    sidebar()
                        .frame(width: clampedWidth)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isVisible {
                    LivePlaybackSidebarResizeHandle(
                        width: $sidebarWidth,
                        totalWidth: geometry.size.width,
                        accessibilityLabel: "Mapping panel width",
                        onResizeEnded: {
                            persistSidebarWidth(totalWidth: geometry.size.width)
                        }
                    )
                    .offset(
                        x: -(clampedWidth + 0.25 - (LivePlaybackSidebarMetrics.resizeHitAreaWidth / 2))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .onChange(of: geometry.size.width) { _, newWidth in
                let clamped = LivePlaybackSidebarMetrics.clampedSidebarWidth(sidebarWidth, totalWidth: newWidth)
                guard clamped != sidebarWidth else { return }
                sidebarWidth = clamped
                persistSidebarWidth(totalWidth: newWidth)
            }
        }
        .animation(AppAnimation.springSmooth, value: isVisible)
        .animation(.none, value: sidebarWidth)
        .onAppear {
            sidebarWidth = LivePlaybackSidebarMetrics.sidebarWidth(fromStorage: storedSidebarWidth)
        }
    }

    private func persistSidebarWidth(totalWidth: CGFloat) {
        storedSidebarWidth = LivePlaybackSidebarMetrics.storageValue(
            forWidth: sidebarWidth,
            totalWidth: totalWidth
        )
    }
}

#if os(macOS)
struct LivePlaybackMixerSplitLayout<MainContent: View>: View {
    @Binding var mixerDetent: LiveGroupMixerDetent
    let onLiveVolumeChange: (UUID?, Double) -> Void
    let onMixChange: () -> Void
    @ViewBuilder let mainContent: () -> MainContent

    var body: some View {
        GeometryReader { geometry in
            if mixerDetent == .visible {
                VSplitView {
                    mainContent()
                        .frame(minHeight: LiveGroupMixerDetent.minimumMainHeight)

                    LiveGroupMixerPanel(
                        onLiveVolumeChange: onLiveVolumeChange,
                        onMixChange: onMixChange
                    )
                        .frame(
                            minHeight: LiveGroupMixerDetent.minimumMixerHeight,
                            idealHeight: geometry.size.height * LiveGroupMixerDetent.heightFraction
                        )
                }
            } else {
                mainContent()
            }
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 0.5)
        }
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
                .background(titleColor)
        }
        .frame(width: stripWidth, height: stripHeight, alignment: .bottom)
    }
}
