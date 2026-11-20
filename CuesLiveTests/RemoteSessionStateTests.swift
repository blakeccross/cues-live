import XCTest
@testable import CuesLive

final class RemoteSessionStateTests: XCTestCase {
    func testRoundTripKeepsSoloState() throws {
        var state = RemoteSessionState.empty
        let groupID = UUID()
        state.soloedGroupIDs = [groupID]
        state.ungroupedIsSoloed = true

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RemoteSessionState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    func testDecodesStateFromHostWithoutSolo() throws {
        let data = try JSONEncoder().encode(RemoteSessionState.empty)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "soloedGroupIDs")
        json.removeValue(forKey: "ungroupedIsSoloed")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(RemoteSessionState.self, from: legacy)

        XCTAssertEqual(decoded.soloedGroupIDs, [])
        XCTAssertFalse(decoded.ungroupedIsSoloed)
    }

    func testGroupDecodesWithoutSoloFromOlderHost() throws {
        let group = RemoteGroupDTO(
            id: UUID(),
            name: "Drums",
            sortOrder: 0,
            volume: 1,
            isMuted: false,
            isMixable: true
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as? [String: Any]
        )
        json.removeValue(forKey: "isSoloed")

        let decoded = try JSONDecoder().decode(
            RemoteGroupDTO.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertFalse(decoded.isSoloed)
    }
}
