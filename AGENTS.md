# AGENTS.md

Rules for anyone (human or agent) changing this repository. `CLAUDE.md` is a symlink to this file.

cues.live is a SwiftUI app for macOS 14+ and iPadOS 17+ that plays multitrack stems live. The
project builds in Swift 5 language mode with Xcode 26+. See `README.md` for features and layout.

## Build and test

```bash
# macOS build (Debug)
xcodebuild -project CuesLive.xcodeproj -scheme CuesLive -destination 'platform=macOS' build

# macOS unit tests
xcodebuild -project CuesLive.xcodeproj -scheme CuesLive -destination 'platform=macOS' test

# iOS build (catches #if os(...) mistakes)
xcodebuild -project CuesLive.xcodeproj -scheme CuesLive -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

- Build **both** platforms before declaring a change done. Most view files contain `#if os(macOS)` / `#if os(iOS)` branches.
- Run the test target after touching anything under `Services/` or `Models/`.
- Three tests drive the real audio engine through a capture tap and are timing-sensitive. They can fail
  on a loaded machine or with certain output devices, independent of code changes:
  `SectionCueEngineTests.testCuedSectionsKeepClickTrainIntactWithArrangementMapping`,
  `SectionCueEngineTests.testCuedSectionsKeepClickTrainIntactForGeneratedClick` and
  `UserProjectCueTests.testCueRefrainWhilePlayingPraiseKeepsClickIntact`. Re-run them in isolation, and
  compare against an untouched checkout, before treating a failure as yours.
- The build must stay at zero Swift warnings. The only accepted warnings come from `ThirdParty/`.

## Registering source files

The Xcode project uses an explicit file list, not a synchronized folder. **A new `.swift` file is not
compiled until it is added to the project.** Use the helper rather than editing `project.pbxproj` by hand:

```bash
Scripts/pbxproj-sources.py add CuesLive/Views/Foo/NewView.swift
Scripts/pbxproj-sources.py remove CuesLive/Views/Foo/OldView.swift
```

Files under `CuesLive/` are added to both app targets (`CuesLive` and `CuesLiveAppStore`); files under
`CuesLiveTests/` go to the test target. The helper locates the group through an existing sibling file, so
the first file in a brand-new directory has to be added in Xcode.

When you delete a file, `git rm` it **and** run `remove`.

## File organization

- **One primary type per file**, named after that type. Small private helpers that only the primary
  type uses may live in the same file.
- **Target under 400 lines per file; never add to a file that is already over 800.** When a file grows
  past the target, split it before adding more.
- Split a large type across files with extensions named `Type+Topic.swift`
  (`EditView+Clips.swift`, `LivePlaybackView+Files.swift`). Stored properties and `body` stay in the
  base file; each extension file holds one cohesive group of behaviour.
- Members used from another file of the same type cannot be `private`. Drop the modifier on exactly
  those members and leave everything else `private`. Do not widen access "just in case".
- Platform-specific wrappers (`NSViewRepresentable`, `UIViewRepresentable`) live in their own file
  with the whole file body inside `#if os(...)`, or at least with their SwiftUI entry point outside the guard.
- Keep the folder layout in `README.md` accurate: `Models/` (SwiftData + document structs), `Services/<Area>/`,
  `ViewModels/`, `Views/<Screen>/`, `DesignSystem/`.
- Functions and `body` properties should stay under about 60 lines. Extract named subviews or helper
  methods instead of nesting deeper.

## Dead code

- Delete unused declarations when you find them; do not comment them out or leave `// unused` notes.
- Before removing something public-looking, grep the whole repo including `CuesLiveTests/`.
- When a feature is replaced (for example, a second audio engine superseding in-engine overlap playback),
  remove the superseded code path in the same change.
- No `TODO`/`FIXME` markers in committed code; either do it or open an issue.
- No `print` debugging. Use `os.Logger` with a `live.cues` subsystem when logging is needed.

## Swift style

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

- **Clarity at the point of use.** Name by role, not type: `var greeting`, not `var string`.
- Methods with side effects read as imperative verbs (`x.sort()`); without side effects, as nouns
  (`x.distance(to:)`). Mutating/non-mutating pairs use `sort()`/`sorted()`, `formUnion`/`union`.
- Factory methods start with `make`. Capability protocols end in `-able`, `-ible`, `-ing`.
- Omit needless words and words that repeat type information. Label all arguments except when they
  cannot be distinguished (`min(a, b)`) or for value-preserving conversions (`Int64(x)`).
- Prefer `count(where:)` over `filter { }.count`, `first(where:)` over `filter { }.first`.
- No force unwraps, `try!`, or `as!` in app code. Tests may use them for fixtures.
- Doc comments (`///`) on types and on any method whose contract is not obvious from the signature.
  Keep inline comments for *why*, not *what*.
- Group related members with `// MARK: -` only inside files that genuinely need navigation; prefer
  splitting the file.

## Concurrency

The app is in Swift 5 language mode, so the compiler does not enforce isolation. Write code as if it did,
so a future move to Swift 6 is mechanical:

- UI types, view models, and anything observed by SwiftUI are `@MainActor`.
  Apply the attribute to the type, not to individual members.
- Mutable shared state outside the main actor lives in an `actor` or behind an explicit serial
  `DispatchQueue`. Do not create a stateless actor; use a plain async function instead.
- `async` does not mean background. Move CPU-heavy work (decoding, peak scanning, rendering) off the
  main actor explicitly with `Task.detached` or a dedicated queue.
- Never block with `DispatchSemaphore` or `group.wait()` from an `async` context or on the main thread.
- Long loops in async code check `Task.checkCancellation()` or `Task.isCancelled`.
- Prefer `await mainActorFunction()` over `await MainActor.run { }`.
- Global and static mutable state must be `@MainActor`, a `let`, or protected by an actor.
- Pass `Sendable` value types (structs, enums) across isolation boundaries; do not add `@unchecked Sendable`
  to silence a warning.

### Real-time audio

Code that runs on the audio render thread (`TrackMemoryPlayer`, `DecodedStemBuffer`, `AudioPlaybackTransport`,
`LTCGenerator`, source-node render blocks) must not allocate, lock, await, or touch Swift classes that
could be deallocated. Keep that code synchronous and self-contained, and keep anything observable by
SwiftUI out of it.

## SwiftUI

- Views are structs with `let` inputs and `@State` for local UI state only. Put logic in services and
  view models under `Services/` and `ViewModels/`.
- Use the design system (`AppColors`, `AppSpacing`, `AppTypography`, `AppRadius`, `App*` components)
  instead of literal colors, paddings, and fonts.
- Platform differences go through `#if os(macOS)` / `#if os(iOS)` at the smallest scope that works.
- Mark views `@MainActor` explicitly when they hold `@StateObject` or observable state; Swift 6 will no
  longer infer it from property wrappers.

## Availability

- Deployment targets are macOS 14 and iOS 17. Gate newer APIs with `if #available(macOS 15, iOS 18, *)`
  (and a fallback), not by raising the deployment target.
- Deprecate rather than delete public-facing document formats: `.cueslive`, `.cueshow`, and the legacy
  `.cueset` extension must keep loading. Add a migration and a test when the schema changes.

## Data and files

- Song data is authoritative in `.cueslive` project files; SwiftData is an index. Writes go through
  `ProjectFileStore` / `SongProjectBridge`, never directly to the model from a view.
- Audio stays on disk and is referenced through `MediaReference`. Do not copy stems into the bundle.
- Any new persisted field needs a default so old files still decode.

## Tests

- XCTest, one `*Tests.swift` per unit under test, in `CuesLiveTests/`.
- Test services and models directly. Do not test SwiftUI layout.
- New behaviour in `Services/` or `Models/` ships with a test. Bug fixes add a regression test first.

## Git

- Small, single-purpose commits with an imperative subject line.
- Do not commit `DerivedData`, `*.profraw`, or Xcode user state.
- `ThirdParty/` holds git submodules; do not edit vendored code, pin a new commit instead.
