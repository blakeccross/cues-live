import SwiftData
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

    @MainActor
    func testStereoTestSpeaksOnBothChannelsAndStopDoesNotCrash() async {
        let peaks = await OutputChannelTestPlayer.shared.measureChannelPeaks(
            destination: .stereoPair(startChannel: 1),
            channelCount: 2
        )
        XCTAssertGreaterThanOrEqual(peaks.count, 2, "expected a stereo meter, got \(peaks)")
        XCTAssertGreaterThan(peaks[0], 0.01, "output 1 was silent: \(peaks)")
        XCTAssertGreaterThan(peaks[1], 0.01, "output 2 was silent: \(peaks)")
    }

    @MainActor
    func testMonoOutputTwoSpeaksOnlyOnTheSecondChannel() async {
        let peaks = await OutputChannelTestPlayer.shared.measureChannelPeaks(
            destination: .mono(channel: 2),
            channelCount: 2
        )
        XCTAssertGreaterThanOrEqual(peaks.count, 2, "expected a stereo meter, got \(peaks)")
        XCTAssertLessThan(peaks[0], 0.01, "output 2 leaked onto output 1: \(peaks)")
        XCTAssertGreaterThan(peaks[1], 0.01, "output 2 was silent: \(peaks)")
    }

    @MainActor
    func testBuiltInDevicePlaysOutputTwoOnlyOnTheSecondChannel() async {
        let devices = Self.listenerOutputDevices()
        XCTAssertFalse(devices.isEmpty, "no output device")
        for device in devices {
            let peaks = await OutputChannelTestPlayer.shared.measureChannelPeaks(
                destination: .mono(channel: 2),
                channelCount: max(device.channelCount, 2),
                deviceUID: device.id
            )
            XCTAssertGreaterThanOrEqual(peaks.count, 2, "expected stereo hardware, got \(peaks) on \(device.name)")
            XCTAssertLessThan(peaks[0], 0.01, "output 2 leaked onto output 1 on \(device.name): \(peaks)")
            XCTAssertGreaterThan(
                peaks[1],
                0.01,
                "output 2 was silent on \(device.name): \(peaks) \(OutputChannelTestPlayer.shared.lastGraphDescription)"
            )
        }
    }

    @MainActor
    func testBuiltInDevicePlaysStereoPairOnBothChannels() async {
        let devices = Self.listenerOutputDevices()
        XCTAssertFalse(devices.isEmpty, "no output device")
        for device in devices {
            let peaks = await OutputChannelTestPlayer.shared.measureChannelPeaks(
                destination: .stereoPair(startChannel: 1),
                channelCount: max(device.channelCount, 2),
                deviceUID: device.id
            )
            XCTAssertGreaterThanOrEqual(peaks.count, 2, "expected stereo hardware, got \(peaks) on \(device.name)")
            XCTAssertGreaterThan(peaks[0], 0.01, "output 1 was silent on \(device.name): \(peaks)")
            XCTAssertGreaterThan(peaks[1], 0.01, "output 2 was silent on \(device.name): \(peaks)")
        }
    }

    @MainActor
    func testStartOnBuiltInOutputThenStopWhilePlaying() async {
        let devices = AudioOutputDeviceService.availableDevices()
        let device = Self.builtInOutputDevice() ?? devices.first
        let routeID = UUID()
        OutputChannelTestPlayer.shared.start(
            routeID: routeID,
            destination: .mono(channel: 2),
            deviceUID: device?.id,
            channelCount: max(device?.channelCount ?? 2, 2)
        )

        var becameAudible = false
        for _ in 0..<50 {
            if OutputChannelTestPlayer.shared.isAudible {
                becameAudible = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(
            becameAudible,
            "test never became audible on \(device?.name ?? "no device") (\(devices.map(\.name)))"
        )
        OutputChannelTestPlayer.shared.stop()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(OutputChannelTestPlayer.shared.isTesting(routeID))
        XCTAssertFalse(OutputChannelTestPlayer.shared.isAudible)
    }

    @MainActor
    func testStopDuringSpeechDoesNotCrash() async {
        let routeID = UUID()
        OutputChannelTestPlayer.shared.start(
            routeID: routeID,
            destination: .stereoPair(startChannel: 1),
            deviceUID: nil,
            channelCount: 2
        )
        try? await Task.sleep(nanoseconds: 20_000_000)
        OutputChannelTestPlayer.shared.stop()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(OutputChannelTestPlayer.shared.isTesting(routeID))
    }

    func testMonoOutputTwoUsesTheSecondHardwareChannel() {
        XCTAssertEqual(
            OutputDestination.mono(channel: 2).testChannelIndexes(outputChannelCount: 2),
            [1]
        )
    }

    func testStereoPairUsesBothHardwareChannels() {
        XCTAssertEqual(
            OutputDestination.stereoPair(startChannel: 1).testChannelIndexes(outputChannelCount: 2),
            [0, 1]
        )
    }

    func testMonoDestinationTestPhraseNamesThatChannel() {
        XCTAssertEqual(OutputDestination.mono(channel: 1).testPhrase, "Testing Output 1")
    }

    func testStereoDestinationTestPhraseNamesBothChannels() {
        XCTAssertEqual(
            OutputDestination.stereoPair(startChannel: 1).testPhrase,
            "Testing Output 1 and 2"
        )
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

    func testEachDeviceRemembersItsOwnOutputRoutes() throws {
        let container = try makeRoutingContainer()
        let context = container.mainContext
        let groupID = UUID()

        OutputRoutingStore.setSelectedDevice(uid: "speakers", in: context)
        OutputRoutingStore.setRoute(.mono(channel: 2), for: groupID, deviceUID: "speakers", in: context)
        OutputRoutingStore.setRoute(
            .stereoPair(startChannel: 3),
            for: OutputRoutingStore.ungroupedRouteID,
            deviceUID: "speakers",
            in: context
        )

        OutputRoutingStore.setSelectedDevice(uid: "headphones", in: context)
        OutputRoutingStore.setRoute(.mono(channel: 1), for: groupID, deviceUID: "headphones", in: context)

        XCTAssertEqual(
            OutputRoutingStore.route(for: groupID, deviceUID: "speakers", in: context),
            .mono(channel: 2)
        )
        XCTAssertEqual(
            OutputRoutingStore.ungroupedRoute(deviceUID: "speakers", in: context),
            .stereoPair(startChannel: 3)
        )
        XCTAssertEqual(
            OutputRoutingStore.route(for: groupID, deviceUID: "headphones", in: context),
            .mono(channel: 1)
        )
        XCTAssertEqual(
            OutputRoutingStore.ungroupedRoute(deviceUID: "headphones", in: context),
            .defaultDestination
        )

        OutputRoutingStore.setSelectedDevice(uid: "speakers", in: context)
        let snapshot = OutputRoutingStore.snapshot(in: context, channelCount: 8)
        XCTAssertEqual(snapshot.deviceUID, "speakers")
        XCTAssertEqual(snapshot.routesByGroupID[groupID], .mono(channel: 2))
        XCTAssertEqual(snapshot.ungroupedDestination, .stereoPair(startChannel: 3))
    }

    func testRoutesSavedBeforePerDeviceMemoryStayWithTheSelectedDevice() throws {
        let container = try makeRoutingContainer()
        let context = container.mainContext
        let groupID = UUID()
        OutputRoutingStore.setSelectedDevice(uid: "speakers", in: context)
        context.insert(GroupOutputRoute(groupID: groupID, destination: .mono(channel: 4)))
        try context.save()

        let snapshot = OutputRoutingStore.snapshot(in: context, channelCount: 8)
        XCTAssertEqual(snapshot.routesByGroupID[groupID], .mono(channel: 4))

        OutputRoutingStore.setSelectedDevice(uid: "headphones", in: context)
        XCTAssertEqual(
            OutputRoutingStore.route(for: groupID, deviceUID: "speakers", in: context),
            .mono(channel: 4)
        )
        XCTAssertEqual(
            OutputRoutingStore.route(for: groupID, deviceUID: "headphones", in: context),
            .defaultDestination
        )
    }

    private func makeRoutingContainer() throws -> ModelContainer {
        let schema = Schema(PersistenceController.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func builtInOutputDevice() -> AudioOutputDevice? {
        listenerOutputDevices().first ?? AudioOutputDeviceService.availableDevices().first
    }

    /// Speakers and headphones the user actually listens on. Skips virtual devices.
    private static func listenerOutputDevices() -> [AudioOutputDevice] {
        AudioOutputDeviceService.availableDevices().filter { device in
            let name = device.name.lowercased()
            if name.contains("blackhole") || name.contains("aggregate") { return false }
            return name.contains("speaker")
                || name.contains("headphone")
                || name.contains("airpod")
                || name.contains("macbook")
        }
    }
}
