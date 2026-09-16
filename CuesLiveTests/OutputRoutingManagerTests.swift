import XCTest
@testable import CuesLive

final class OutputRoutingManagerTests: XCTestCase {
    func testMonoChannelMapWorksOnStereoOnlyDevice() {
        let map = OutputRoutingManager.channelMap(
            for: .mono(channel: 1),
            outputChannelCount: 2
        )

        XCTAssertEqual(map.map(\.intValue), [0, -1], "a group pinned to mono channel 1 must not also feed channel 2 on a plain stereo device")
    }

    func testMonoChannelTwoOnStereoOnlyDeviceIsolatesRightChannel() {
        let map = OutputRoutingManager.channelMap(
            for: .mono(channel: 2),
            outputChannelCount: 2
        )

        XCTAssertEqual(map.map(\.intValue), [-1, 0])
    }

    func testStereoPairChannelMapPlacesSourceChannelsOnHardwarePair() {
        let map = OutputRoutingManager.channelMap(
            for: .stereoPair(startChannel: 3),
            outputChannelCount: 8
        )

        XCTAssertEqual(map.map(\.intValue), [-1, -1, 0, 1, -1, -1, -1, -1])
    }

    func testMonoChannelMapPlacesLeftOnSelectedHardwareChannel() {
        let map = OutputRoutingManager.channelMap(
            for: .mono(channel: 5),
            outputChannelCount: 8
        )

        XCTAssertEqual(map.map(\.intValue), [-1, -1, -1, -1, 0, -1, -1, -1])
    }

    func testOutOfRangeDestinationFallsBackToFirstStereoPair() {
        let map = OutputRoutingManager.channelMap(
            for: .stereoPair(startChannel: 9),
            outputChannelCount: 8
        )

        XCTAssertEqual(map.map(\.intValue), [0, 1, -1, -1, -1, -1, -1, -1])
    }

    func testDefaultStereoMap() {
        XCTAssertEqual(
            OutputRoutingManager.defaultStereoMap(4).map(\.intValue),
            [0, 1, -1, -1]
        )
    }

    func testMonoStereoPairUsesDualMonoInsteadOfMissingInputChannel() {
        let map = OutputRoutingManager.channelMap(
            for: .stereoPair(startChannel: 1),
            outputChannelCount: 34,
            sourceChannelCount: 1
        )

        XCTAssertEqual(map[0].intValue, 0)
        XCTAssertEqual(map[1].intValue, 0, "mono stems must not reference input channel 1")
        XCTAssertTrue(map.dropFirst(2).allSatisfy { $0.intValue == -1 })
    }

    func testDefaultStereoMapForMonoSource() {
        XCTAssertEqual(
            OutputRoutingManager.defaultStereoMap(4, sourceChannelCount: 1).map(\.intValue),
            [0, 0, -1, -1]
        )
    }

    func testSnapshotWithAllDefaultRoutingDoesNotRequireChannelMap() {
        let snapshot = OutputRoutingSnapshot(
            deviceUID: nil,
            routesByGroupID: [UUID(): .defaultDestination],
            ungroupedDestination: .defaultDestination,
            channelCount: 2
        )

        XCTAssertFalse(snapshot.hasNonDefaultRouting)
    }

    func testSnapshotWithAMonoGroupRouteRequiresChannelMap() {
        let snapshot = OutputRoutingSnapshot(
            deviceUID: nil,
            routesByGroupID: [UUID(): .mono(channel: 1)],
            ungroupedDestination: .defaultDestination,
            channelCount: 2
        )

        XCTAssertTrue(snapshot.hasNonDefaultRouting)
    }
}
