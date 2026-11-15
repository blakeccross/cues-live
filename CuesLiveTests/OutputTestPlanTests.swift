import XCTest
@testable import CuesLive

final class OutputTestPlanTests: XCTestCase {
    func testAllScopeListsEveryHardwareChannelAsMono() {
        let plan = OutputTestPlan(scope: .all)

        XCTAssertEqual(
            plan.destinations(channelCount: 4, routed: []),
            [.mono(channel: 1), .mono(channel: 2), .mono(channel: 3), .mono(channel: 4)]
        )
    }

    func testInUseScopeDropsUnroutedDuplicateAndUnreachableOutputs() {
        let plan = OutputTestPlan(scope: .inUse)
        let routed: [OutputDestination] = [
            .mono(channel: 3),
            .none,
            .stereoPair(startChannel: 1),
            .stereoPair(startChannel: 1),
            .stereoPair(startChannel: 7)
        ]

        XCTAssertEqual(
            plan.destinations(channelCount: 4, routed: routed),
            [.stereoPair(startChannel: 1), .mono(channel: 3)]
        )
    }

    func testInUseScopeOrdersStereoPairBeforeMonoOnTheSameChannel() {
        let plan = OutputTestPlan(scope: .inUse)

        XCTAssertEqual(
            plan.destinations(channelCount: 2, routed: [.mono(channel: 1), .stereoPair(startChannel: 1)]),
            [.stereoPair(startChannel: 1), .mono(channel: 1)]
        )
    }

    func testAnnouncingAllAtOnceSplitsInUseOutputsIntoMonoChannels() {
        let plan = OutputTestPlan(timing: .simultaneous, signal: .announce, scope: .inUse)
        let routed: [OutputDestination] = [.mono(channel: 2), .stereoPair(startChannel: 1), .stereoPair(startChannel: 5)]

        XCTAssertEqual(
            plan.destinations(channelCount: 6, routed: routed),
            [.mono(channel: 1), .mono(channel: 2), .mono(channel: 5), .mono(channel: 6)]
        )
    }

    func testOtherModesKeepInUseStereoPairs() {
        let routed: [OutputDestination] = [.stereoPair(startChannel: 1)]

        for plan in [
            OutputTestPlan(timing: .series, signal: .announce, scope: .inUse),
            OutputTestPlan(timing: .simultaneous, signal: .noise, scope: .inUse)
        ] {
            XCTAssertEqual(plan.destinations(channelCount: 2, routed: routed), [.stereoPair(startChannel: 1)])
        }
    }

    func testDestinationNamesMatchTheSpokenPhrase() {
        XCTAssertEqual(OutputDestination.mono(channel: 5).name, "Output 5")
        XCTAssertEqual(OutputDestination.stereoPair(startChannel: 3).name, "Output 3 and 4")
        XCTAssertEqual(OutputDestination.none.testPhrase, "")
    }
}
