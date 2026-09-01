import XCTest
@testable import CuesLive

final class TrackGroupStoreTests: XCTestCase {
    private func defaultGroups() -> [TrackGroup] {
        TrackGroupStore.defaultNames.enumerated().map { index, name in
            let group = TrackGroup(
                name: name,
                sortOrder: index,
                paletteKey: TrackGroupStore.defaultPaletteKey(forGroupName: name)
            )
            group.setKeywordList(TrackGroupStore.defaultKeywords(forGroupName: name))
            return group
        }
    }

    func testProToolsStyleStemNamesMapToExpectedGroups() {
        let groups = defaultGroups()
        let expectations: [(String, String)] = [
            ("session_1-Kick In", "Drums"),
            ("session_2-Kick Out", "Drums"),
            ("session_3-Snare Top", "Drums"),
            ("session_4-Snare Bot", "Drums"),
            ("session_5-Rack Tom", "Drums"),
            ("session_6-Floor Tom", "Drums"),
            ("session_7-Hat", "Drums"),
            ("session_8-Knee", "Drums"),
            ("session_9-Overhead", "Drums"),
            ("session_74-Kick Trig", "Drums"),
            ("session_75-Snr Trig", "Drums"),
            ("session_76-Flr Tom Trig", "Drums"),
            ("session_77-Rack Tom Trig", "Drums"),
            ("session_11-Bass DI", "Bass"),
            ("session_14-EGTR 1A", "EG"),
            ("session_16-EGTR 2A", "EG"),
            ("session_17-EGTR 2B", "EG"),
            ("session_22-AGTR 1", "AG"),
            ("session_24-Keys 1 L_R", "Keys"),
            ("session_31-Trk Pads L_R", "Synth"),
            ("session_32-Trk Perc L_R", "Percussion"),
            ("session_33-V1 Matt", "LV"),
            ("session_35-V3 Elly", "LV"),
            ("session_36-V4 Dani", "LV"),
            ("session_37-V5 Tim", "LV"),
            ("session_44-Announce 1 HH", "LV"),
            ("session_45-Announce 2 HH", "LV"),
            ("session_55-Crowd L", "Other"),
            ("session_56-Crowd R", "Other"),
        ]

        for (trackName, expectedGroupName) in expectations {
            let matched = TrackGroupStore.guessGroup(for: trackName, from: groups)
            XCTAssertEqual(
                matched?.name,
                expectedGroupName,
                "\(trackName) should map to \(expectedGroupName)"
            )
        }
    }
}
