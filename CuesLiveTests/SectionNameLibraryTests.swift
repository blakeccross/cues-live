import XCTest
@testable import CuesLive

@MainActor
final class SectionNameLibraryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SectionNameLibraryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStartsWithDefaults() {
        let library = SectionNameLibrary(defaults: defaults)
        XCTAssertEqual(library.names, SectionNameLibrary.defaultNames)
    }

    func testAddPersistsAcrossInstances() {
        let library = SectionNameLibrary(defaults: defaults)
        XCTAssertTrue(library.add("  Vamp "))

        let reloaded = SectionNameLibrary(defaults: defaults)
        XCTAssertEqual(reloaded.names.last, "Vamp")
    }

    func testAddRejectsEmptyAndCaseInsensitiveDuplicates() {
        let library = SectionNameLibrary(defaults: defaults)
        XCTAssertFalse(library.add("   "))
        XCTAssertFalse(library.add("chorus"))
        XCTAssertEqual(library.names, SectionNameLibrary.defaultNames)
    }

    func testRenameAllowsChangingCaseOfSameEntry() {
        let library = SectionNameLibrary(defaults: defaults)
        XCTAssertTrue(library.rename(at: 0, to: "INTRO"))
        XCTAssertEqual(library.names.first, "INTRO")
        XCTAssertFalse(library.rename(at: 0, to: "Verse"))
    }

    func testRemoveAndMove() {
        let library = SectionNameLibrary(defaults: defaults)
        library.remove(atOffsets: [0])
        XCTAssertEqual(library.names.first, "Verse")

        library.move(fromOffsets: [0], toOffset: 2)
        XCTAssertEqual(Array(library.names.prefix(2)), ["Pre-Chorus", "Verse"])
        XCTAssertEqual(SectionNameLibrary(defaults: defaults).names, library.names)
    }

    func testRestoreDefaults() {
        let library = SectionNameLibrary(defaults: defaults)
        library.remove(atOffsets: [0, 1, 2])
        library.restoreDefaults()

        XCTAssertEqual(library.names, SectionNameLibrary.defaultNames)
        XCTAssertEqual(SectionNameLibrary(defaults: defaults).names, SectionNameLibrary.defaultNames)
    }
}
