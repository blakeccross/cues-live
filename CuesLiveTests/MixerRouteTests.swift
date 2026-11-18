import XCTest
@testable import CuesLive

final class MixerRouteTests: XCTestCase {
    func testNoOutputFeedsNoChannels() {
        XCTAssertEqual(MixerRoute(destination: .none, outputChannelCount: 2), .silent)
    }

    func testStereoPairLandsOnItsTwoOutputs() {
        let route = MixerRoute(destination: .stereoPair(startChannel: 3), outputChannelCount: 8)

        XCTAssertEqual(route.left, 2)
        XCTAssertEqual(route.right, 3)
    }

    func testMonoOutputOneOnAStereoDeviceDoesNotAlsoFeedOutputTwo() {
        let route = MixerRoute(destination: .mono(channel: 1), outputChannelCount: 2)

        XCTAssertEqual(route.left, 0)
        XCTAssertNil(route.right)
    }

    func testMonoOutputTwoOnAStereoDeviceUsesOnlyTheSecondOutput() {
        let route = MixerRoute(destination: .mono(channel: 2), outputChannelCount: 2)

        XCTAssertEqual(route.left, 1)
        XCTAssertNil(route.right)
    }

    func testMonoOutputOnAWideDevice() {
        XCTAssertEqual(MixerRoute(destination: .mono(channel: 5), outputChannelCount: 8).left, 4)
    }

    func testDestinationsPastTheDeviceFallBackToOutputsOneAndTwo() {
        for destination in [OutputDestination.stereoPair(startChannel: 9), .stereoPair(startChannel: 8), .mono(channel: 9)] {
            let route = MixerRoute(destination: destination, outputChannelCount: 8)
            XCTAssertEqual(route.left, 0, "\(destination)")
            XCTAssertEqual(route.right, 1, "\(destination)")
        }
    }

    func testDeviceNarrowerThanStereoIsTreatedAsStereo() {
        let route = MixerRoute(destination: .defaultDestination, outputChannelCount: 1)

        XCTAssertEqual(route.left, 0)
        XCTAssertEqual(route.right, 1)
    }
}
