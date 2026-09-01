import XCTest
@testable import CuesLive

@MainActor
final class InputMappingControllerTests: XCTestCase {
    private var store: InputMappingStore!
    private var controller: InputMappingController!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "InputMappingControllerTests.\(UUID().uuidString)")!
        defaults.set(Data("[]".utf8), forKey: "inputMapping.mappings")
        store = InputMappingStore(defaults: defaults)
        controller = InputMappingController(store: store, bindsHardware: false)
    }

    func testAssignmentBadgeUsesKeyOrMIDIForCurrentSession() {
        store.assignKey(Self.key("A", code: 0), to: .playPause)
        store.assignMIDI(MIDINoteBinding(note: 60, channel: 1, sourceName: nil), to: .playPause)

        XCTAssertNil(controller.liveAssignmentBadge(for: .playPause))

        controller.beginKeyMapping()
        XCTAssertEqual(controller.liveAssignmentBadge(for: .playPause), "A")
        XCTAssertNil(controller.liveAssignmentBadge(for: .stop))

        controller.beginMIDIMapping()
        XCTAssertEqual(controller.liveAssignmentBadge(for: .playPause), "C4")
    }

    func testKeyLearnAssignsSelectedActionAndStaysInSession() {
        controller.beginKeyMapping()
        controller.selectAction(.fade)

        XCTAssertTrue(controller.handleKey(Self.key("F", code: 3)))
        XCTAssertEqual(store.mapping(for: .fade)?.key?.keyName, "F")
        XCTAssertNil(controller.pendingAction)
        XCTAssertEqual(controller.session, .keyMapping)
        XCTAssertEqual(controller.liveAssignmentBadge(for: .fade), "F")
    }

    func testKeyLearnDoesNothingUntilAControlIsSelected() {
        controller.beginKeyMapping()
        XCTAssertFalse(controller.handleKey(Self.key("A", code: 0)))
        XCTAssertNil(store.mapping(for: .playPause))
    }

    func testMIDIIsIgnoredDuringKeyMapping() {
        controller.beginKeyMapping()
        controller.selectAction(.loop)
        controller.handleMIDI(MIDINoteBinding(note: 36, channel: 1, sourceName: nil))

        XCTAssertNil(store.mapping(for: .loop))
        XCTAssertEqual(controller.pendingAction, .loop)
    }

    func testSettingsLearnEndsSessionAfterAssign() {
        controller.startSettingsLearn(action: .stop, session: .keyMapping)
        XCTAssertTrue(controller.handleKey(Self.key("S", code: 1)))
        XCTAssertEqual(store.mapping(for: .stop)?.key?.keyName, "S")
        XCTAssertEqual(controller.session, .idle)
        XCTAssertNil(controller.liveAssignmentBadge(for: .stop))
    }

    func testIdleKeyTriggersBoundAction() {
        store.assignKey(Self.key("P", code: 35), to: .playPause)
        var received: MappableLiveAction?
        _ = controller.activateLiveSession { received = $0 }

        XCTAssertTrue(controller.handleKey(Self.key("P", code: 35)))
        XCTAssertEqual(received, .playPause)
    }

    func testIdleKeyDoesNotFireWhenPlaybackActionsAreDisabled() {
        store.assignKey(Self.key("P", code: 35), to: .playPause)
        var received: MappableLiveAction?
        _ = controller.activateLiveSession { received = $0 }
        controller.arePlaybackActionsEnabled = false

        XCTAssertFalse(controller.handleKey(Self.key("P", code: 35)))
        XCTAssertNil(received)
    }

    func testEscapeClearsPendingThenExitsMapping() {
        let escape = KeyBinding(
            keyCode: 53,
            character: "\u{1b}",
            keyName: "Escape",
            command: false,
            shift: false,
            option: false,
            control: false
        )
        controller.beginKeyMapping()
        controller.selectAction(.stop)

        XCTAssertTrue(controller.handleKey(escape))
        XCTAssertNil(controller.pendingAction)
        XCTAssertEqual(controller.session, .keyMapping)

        XCTAssertTrue(controller.handleKey(escape))
        XCTAssertEqual(controller.session, .idle)
    }

    private static func key(_ name: String, code: UInt16) -> KeyBinding {
        KeyBinding(
            keyCode: code,
            character: name.lowercased(),
            keyName: name,
            command: false,
            shift: false,
            option: false,
            control: false
        )
    }
}
