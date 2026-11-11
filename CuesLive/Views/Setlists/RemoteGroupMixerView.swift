import SwiftUI

#if os(iOS)
struct RemoteGroupMixerScreen: View {
    @Bindable var client: RemoteSessionClientService

    var body: some View {
        RemoteGroupMixerView(client: client)
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

struct RemoteGroupMixerView: View {
    @Bindable var client: RemoteSessionClientService

    private let stripWidth: CGFloat = 96

    private var groups: [RemoteGroupDTO] {
        (client.snapshot?.groups ?? []).filter(\.isMixable)
    }

    var body: some View {
        GeometryReader { geometry in
            let stripHeight = max(140, geometry.size.height - AppSpacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(groups) { group in
                        LiveGroupChannelStrip(
                            title: group.name,
                            titleColor: TrackGroupPalette.colors(forPaletteKey: group.paletteKey).body,
                            groupID: group.id,
                            volume: volumeBinding(for: group.id),
                            isMuted: muteBinding(for: group.id),
                            stripHeight: stripHeight,
                            stripWidth: stripWidth,
                            onLiveVolumeChange: { groupID, liveVolume in
                                client.send(.setGroupVolume(
                                    groupID: groupID,
                                    volume: liveVolume,
                                    provisional: true
                                ))
                            },
                            // Commit happens via the volume binding setter on drag end.
                            onMixChange: {}
                        )
                    }

                    LiveGroupChannelStrip(
                        title: "No Group",
                        titleColor: TrackGroupPalette.colors(forPaletteKey: nil).body,
                        groupID: nil,
                        volume: Binding(
                            get: { client.state.ungroupedVolume },
                            set: { newValue in
                                client.send(.setGroupVolume(groupID: nil, volume: newValue, provisional: false))
                            }
                        ),
                        isMuted: Binding(
                            get: { client.state.ungroupedIsMuted },
                            set: { newValue in
                                client.send(.setGroupMuted(groupID: nil, muted: newValue))
                            }
                        ),
                        stripHeight: stripHeight,
                        stripWidth: stripWidth,
                        onLiveVolumeChange: { _, liveVolume in
                            client.send(.setGroupVolume(groupID: nil, volume: liveVolume, provisional: true))
                        },
                        // Commit happens via the volume binding setter on drag end.
                        onMixChange: {}
                    )
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.top, AppSpacing.xs)
            }
            .contentMargins(.bottom, 0, for: .scrollContent)
        }
        .background(AppColors.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.separator)
                .frame(height: 0.5)
        }
    }

    private func volumeBinding(for groupID: UUID) -> Binding<Double> {
        Binding(
            get: {
                client.state.groupVolumes[groupID.uuidString]
                    ?? client.snapshot?.groups.first(where: { $0.id == groupID })?.volume
                    ?? 1
            },
            set: { newValue in
                client.send(.setGroupVolume(groupID: groupID, volume: newValue, provisional: false))
            }
        )
    }

    private func muteBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { client.state.mutedGroupIDs.contains(groupID) },
            set: { newValue in
                client.send(.setGroupMuted(groupID: groupID, muted: newValue))
            }
        )
    }
}
