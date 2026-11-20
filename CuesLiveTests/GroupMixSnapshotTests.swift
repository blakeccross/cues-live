import XCTest
@testable import CuesLive

final class GroupMixSnapshotTests: XCTestCase {
    private let drums = UUID()
    private let keys = UUID()

    func testNothingSilencedWithoutMuteOrSolo() {
        let snapshot = GroupMixSnapshot.default
        XCTAssertFalse(snapshot.hasSolo)
        XCTAssertFalse(snapshot.isSilenced(groupID: drums))
        XCTAssertFalse(snapshot.isSilenced(groupID: nil))
    }

    func testSoloSilencesOtherGroupsAndNoGroup() {
        var snapshot = GroupMixSnapshot.default
        snapshot.soloedGroupIDs = [drums]

        XCTAssertFalse(snapshot.isSilenced(groupID: drums))
        XCTAssertTrue(snapshot.isSilenced(groupID: keys))
        XCTAssertTrue(snapshot.isSilenced(groupID: nil))
    }

    func testSoloingNoGroupSilencesGroups() {
        var snapshot = GroupMixSnapshot.default
        snapshot.ungroupedIsSoloed = true

        XCTAssertFalse(snapshot.isSilenced(groupID: nil))
        XCTAssertTrue(snapshot.isSilenced(groupID: drums))
    }

    func testMuteWinsOverSolo() {
        var snapshot = GroupMixSnapshot.default
        snapshot.soloedGroupIDs = [drums]
        snapshot.mutedGroupIDs = [drums]

        XCTAssertTrue(snapshot.isSilenced(groupID: drums))
    }

    func testTracksIgnoringSoloOnlyFollowMute() {
        var snapshot = GroupMixSnapshot.default
        snapshot.soloedGroupIDs = [drums]

        XCTAssertFalse(snapshot.isSilenced(groupID: keys, ignoresSolo: true))

        snapshot.mutedGroupIDs = [keys]
        XCTAssertTrue(snapshot.isSilenced(groupID: keys, ignoresSolo: true))
    }

    func testReplacingVolumeKeepsSoloState() {
        var snapshot = GroupMixSnapshot.default
        snapshot.soloedGroupIDs = [drums]
        snapshot.ungroupedIsSoloed = true

        let updated = snapshot.replacingVolume(groupID: drums, volume: 0.5)

        XCTAssertEqual(updated.volumeByGroupID[drums], 0.5)
        XCTAssertEqual(updated.soloedGroupIDs, [drums])
        XCTAssertTrue(updated.ungroupedIsSoloed)
    }
}
