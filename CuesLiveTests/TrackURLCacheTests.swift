import XCTest
@testable import CuesLive

@MainActor
final class TrackURLCacheTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/Songs/Song.cueslive")
    private let stem = MediaReference(path: "Audio/Click.wav", pathStyle: .relativeToProject, bookmark: Data([1, 2, 3]))

    func testResolvesARepeatedLookupOnce() {
        var resolveCount = 0
        let cache = TrackURLCache(
            resolve: { _, _ in
                resolveCount += 1
                return URL(fileURLWithPath: "/Songs/Audio/Click.wav")
            },
            fileExists: { _ in true }
        )

        for _ in 0..<5 {
            XCTAssertEqual(cache.url(for: stem, projectFileURL: project)?.path, "/Songs/Audio/Click.wav")
        }
        XCTAssertEqual(resolveCount, 1)
    }

    func testResolvesAgainWhenTheReferenceChanges() {
        var resolved: [MediaReference] = []
        let cache = TrackURLCache(
            resolve: { reference, _ in
                resolved.append(reference)
                return URL(fileURLWithPath: "/Songs/" + reference.path)
            },
            fileExists: { _ in true }
        )
        var relinked = stem
        relinked.path = "Audio/Guide.wav"
        relinked.bookmark = Data([4, 5, 6])

        _ = cache.url(for: stem, projectFileURL: project)
        let url = cache.url(for: relinked, projectFileURL: project)

        XCTAssertEqual(url?.path, "/Songs/Audio/Guide.wav")
        XCTAssertEqual(resolved, [stem, relinked])
    }

    func testResolvesAgainWhenTheProjectMoves() {
        var resolveCount = 0
        let cache = TrackURLCache(
            resolve: { _, projectFileURL in
                resolveCount += 1
                return projectFileURL?.deletingLastPathComponent().appendingPathComponent("Audio/Click.wav")
            },
            fileExists: { _ in true }
        )

        _ = cache.url(for: stem, projectFileURL: project)
        let moved = cache.url(for: stem, projectFileURL: URL(fileURLWithPath: "/Moved/Song.cueslive"))

        XCTAssertEqual(moved?.path, "/Moved/Audio/Click.wav")
        XCTAssertEqual(resolveCount, 2)
    }

    func testResolvesAgainWhenTheCachedFileIsGone() {
        var resolveCount = 0
        var existing: Set<String> = ["/Songs/Audio/Click.wav"]
        let cache = TrackURLCache(
            resolve: { _, _ in
                resolveCount += 1
                return resolveCount == 1
                    ? URL(fileURLWithPath: "/Songs/Audio/Click.wav")
                    : URL(fileURLWithPath: "/Elsewhere/Click.wav")
            },
            fileExists: { existing.contains($0.path) }
        )

        _ = cache.url(for: stem, projectFileURL: project)
        existing = ["/Elsewhere/Click.wav"]
        let url = cache.url(for: stem, projectFileURL: project)

        XCTAssertEqual(url?.path, "/Elsewhere/Click.wav")
        XCTAssertEqual(resolveCount, 2)
    }

    func testDoesNotKeepAMissingFile() {
        var resolveCount = 0
        var isLinked = false
        let cache = TrackURLCache(
            resolve: { _, _ in
                resolveCount += 1
                return isLinked ? URL(fileURLWithPath: "/Songs/Audio/Click.wav") : nil
            },
            fileExists: { _ in true }
        )

        XCTAssertNil(cache.url(for: stem, projectFileURL: project))
        isLinked = true

        XCTAssertNotNil(cache.url(for: stem, projectFileURL: project))
        XCTAssertEqual(resolveCount, 2)
    }
}
