import XCTest
@testable import CuesLive

@MainActor
final class InputMappingStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: InputMappingStore!

    override func setUp() {
        super.setUp()
        let suiteName = "InputMappingStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = InputMappingStore(defaults: defaults)
    }

    func testFirstLaunchLoadsDefaultKeyMappings() {
        XCTAssertEqual(store.mappings.count, InputMappingStore.defaultMappings.count)
        XCTAssertEqual(store.mapping(for: .playPause)?.key?.keyName, "Space")
        XCTAssertEqual(store.mapping(for: .stop)?.key?.keyName, "S")
        XCTAssertEqual(store.mapping(for: .fade)?.key?.keyName, "F")
        XCTAssertEqual(store.mapping(for: .loop)?.key?.keyName, "L")
    }

    func testSavedEmptyMappingsDoNotRestoreDefaults() {
        defaults.set(Data("[]".utf8), forKey: "inputMapping.mappings")
        let reloaded = InputMappingStore(defaults: defaults)
        XCTAssertTrue(reloaded.mappings.isEmpty)
    }

    func testAssigningKeyReplacesPreviousAction() {
        let space = KeyBinding(
            keyCode: 49,
            character: " ",
            keyName: "Space",
            command: false,
            shift: false,
            option: false,
            control: false
        )

        store.assignKey(space, to: .playPause)
        store.assignKey(space, to: .stop)

        XCTAssertNil(store.mapping(for: .playPause)?.key)
        XCTAssertEqual(store.mapping(for: .stop)?.key?.keyName, "Space")
        XCTAssertEqual(store.action(forKey: space), .stop)
    }

    func testAssigningMIDIReplacesPreviousAction() {
        let note = MIDINoteBinding(note: 60, channel: 1, sourceName: "Pad")

        store.assignMIDI(note, to: .fade)
        store.assignMIDI(note, to: .loop)

        XCTAssertNil(store.mapping(for: .fade)?.midi)
        XCTAssertEqual(store.mapping(for: .loop)?.midi?.note, 60)
        XCTAssertEqual(store.action(forMIDI: note), .loop)
    }

    func testClearingKeyLeavesMIDIBinding() {
        store.assignKey(
            KeyBinding(keyCode: 0, character: "a", keyName: "A", command: false, shift: false, option: false, control: false),
            to: .playPause
        )
        store.assignMIDI(MIDINoteBinding(note: 36, channel: 10, sourceName: nil), to: .playPause)
        store.clearKey(for: .playPause)

        XCTAssertNil(store.mapping(for: .playPause)?.key)
        XCTAssertEqual(store.mapping(for: .playPause)?.midi?.note, 36)
    }

    func testClearingLastBindingRemovesMapping() {
        store.assignKey(
            KeyBinding(keyCode: 1, character: "s", keyName: "S", command: false, shift: false, option: false, control: false),
            to: .stop
        )
        store.clearKey(for: .stop)
        XCTAssertNil(store.mapping(for: .stop))
    }

    func testPersistenceRoundTrip() {
        store.assignKey(
            KeyBinding(keyCode: 49, character: " ", keyName: "Space", command: false, shift: false, option: false, control: false),
            to: .playPause
        )
        store.assignMIDI(MIDINoteBinding(note: 48, channel: 2, sourceName: "Keys"), to: .goToSong(0))

        let reloaded = InputMappingStore(defaults: defaults)
        XCTAssertEqual(reloaded.mapping(for: .playPause)?.key?.keyName, "Space")
        XCTAssertEqual(reloaded.mapping(for: .goToSong(0))?.midi?.note, 48)
        XCTAssertEqual(reloaded.mapping(for: .goToSong(0))?.midi?.channel, 2)
        XCTAssertEqual(reloaded.songMappings.count, 1)
    }

    func testMIDINoteDisplayUsesC4For60() {
        XCTAssertEqual(MIDINoteBinding.noteDisplayName(60), "C4")
        XCTAssertEqual(MIDINoteBinding.noteDisplayName(0), "C-1")
        XCTAssertEqual(MIDINoteBinding.noteDisplayName(61), "C#4")
    }

    func testMIDICompactDisplayOmitsDefaultChannel() {
        XCTAssertEqual(
            MIDINoteBinding(note: 60, channel: 1, sourceName: "Pad").compactDisplayName,
            "C4"
        )
        XCTAssertEqual(
            MIDINoteBinding(note: 36, channel: 10, sourceName: nil).compactDisplayName,
            "C2·10"
        )
    }

    func testKeyBindingDisplayIncludesModifiers() {
        let binding = KeyBinding(
            keyCode: 1,
            character: "s",
            keyName: "S",
            command: true,
            shift: true,
            option: false,
            control: false
        )
        XCTAssertEqual(binding.displayName, "⇧⌘S")
    }

    func testKeyBindingMatchesIgnoresCharacterWhenKeyCodesDiffer() {
        let space = KeyBinding(keyCode: 49, character: " ", keyName: "Space", command: false, shift: false, option: false, control: false)
        let other = KeyBinding(keyCode: 0, character: " ", keyName: "Space", command: false, shift: false, option: false, control: false)
        XCTAssertFalse(space.matches(other))
        XCTAssertTrue(space.matches(space))
    }
}
