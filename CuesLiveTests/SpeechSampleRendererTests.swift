import XCTest
@testable import CuesLive

@MainActor
final class SpeechSampleRendererTests: XCTestCase {
    override func tearDown() {
        SpeechSampleRenderer.resetCache()
        super.tearDown()
    }

    func testLoadsIntroSample() async {
        let buffer = await SpeechSampleRenderer.renderMonoStem(for: "Intro")
        XCTAssertNotNil(buffer)
        XCTAssertGreaterThan(buffer?.frameCount ?? 0, 0)
        XCTAssertEqual(buffer?.channelCount, 1)
        XCTAssertEqual(buffer?.sampleRate ?? 0, DecodedStemBuffer.engineSampleRate, accuracy: 0.1)
    }

    func testPreChorusHyphenMapsToBundledSample() async {
        let buffer = await SpeechSampleRenderer.renderMonoStem(for: "Pre-Chorus")
        XCTAssertNotNil(buffer)
        XCTAssertGreaterThan(buffer?.frameCount ?? 0, 0)
    }

    func testMissingHookReturnsNil() async {
        let buffer = await SpeechSampleRenderer.renderMonoStem(for: "Hook")
        XCTAssertNil(buffer)
    }

    func testLoadsBuildDynamicCue() async {
        let buffer = await SpeechSampleRenderer.renderMonoStem(for: "Build")
        XCTAssertNotNil(buffer)
        XCTAssertGreaterThan(buffer?.frameCount ?? 0, 0)
    }

    func testLoadsBreakDynamicCue() async {
        let buffer = await SpeechSampleRenderer.renderMonoStem(for: "Break")
        XCTAssertNotNil(buffer)
        XCTAssertGreaterThan(buffer?.frameCount ?? 0, 0)
    }

    @MainActor
    func testHasSampleMatchesBundledSectionNames() {
        XCTAssertTrue(SpeechSampleRenderer.hasSample(for: "Verse"))
        XCTAssertFalse(SpeechSampleRenderer.hasSample(for: "Definitely Not A Section"))
        XCTAssertFalse(SpeechSampleRenderer.hasSample(for: "  "))
    }
}
