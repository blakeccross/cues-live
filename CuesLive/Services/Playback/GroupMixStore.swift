import Foundation
import SwiftData

struct GroupMixSnapshot: Sendable {
    var volumeByGroupID: [UUID: Float]
    var mutedGroupIDs: Set<UUID>
    var soloedGroupIDs: Set<UUID> = []
    var ungroupedVolume: Float
    var ungroupedIsMuted: Bool
    var ungroupedIsSoloed = false

    static let `default` = GroupMixSnapshot(
        volumeByGroupID: [:],
        mutedGroupIDs: [],
        ungroupedVolume: 1,
        ungroupedIsMuted: false
    )

    var hasSolo: Bool {
        ungroupedIsSoloed || !soloedGroupIDs.isEmpty
    }

    /// Whether a group (nil for "No Group") is silent: muted, or another group is soloed.
    /// Tracks that ignore solo, such as the generated click, only follow mute.
    func isSilenced(groupID: UUID?, ignoresSolo: Bool = false) -> Bool {
        let isMuted = groupID.map(mutedGroupIDs.contains) ?? ungroupedIsMuted
        if isMuted { return true }
        guard hasSolo, !ignoresSolo else { return false }
        let isSoloed = groupID.map(soloedGroupIDs.contains) ?? ungroupedIsSoloed
        return !isSoloed
    }

    func replacingVolume(groupID: UUID?, volume: Float) -> GroupMixSnapshot {
        var snapshot = self
        if let groupID {
            snapshot.volumeByGroupID[groupID] = volume
        } else {
            snapshot.ungroupedVolume = volume
        }
        return snapshot
    }
}

enum GroupMixStore {
    static func snapshot(in context: ModelContext) -> GroupMixSnapshot {
        let groups = TrackGroupStore.sortedGroups(from: context)
        var volumeByGroupID: [UUID: Float] = [:]
        var mutedGroupIDs = Set<UUID>()
        var soloedGroupIDs = Set<UUID>()

        for group in groups {
            if TimecodePlaybackSupport.isTimecodeGroup(group) {
                // LTC must stay at unity; it has no mixer fader.
                volumeByGroupID[group.id] = 1
            } else {
                volumeByGroupID[group.id] = Float(group.volume)
                if group.isMuted {
                    mutedGroupIDs.insert(group.id)
                }
                if group.isSoloed {
                    soloedGroupIDs.insert(group.id)
                }
            }
        }

        let config = OutputRoutingStore.config(in: context)
        return GroupMixSnapshot(
            volumeByGroupID: volumeByGroupID,
            mutedGroupIDs: mutedGroupIDs,
            soloedGroupIDs: soloedGroupIDs,
            ungroupedVolume: Float(config.ungroupedVolume),
            ungroupedIsMuted: config.ungroupedIsMuted,
            ungroupedIsSoloed: config.ungroupedIsSoloed
        )
    }
}
