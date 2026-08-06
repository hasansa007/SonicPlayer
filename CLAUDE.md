# CLAUDE.md - SonicPlayer

## Project Overview

SonicPlayer is a native iOS audio player app (iOS 18.0+) built with **SwiftUI** and **The Composable Architecture (TCA)** v1.26.1. It supports browsing, playing, and recording audio files with a minimalist Sonic teal design.

**Bundle ID:** `com.hasan.sonicplayer`

## Build & Run

```bash
# Open in Xcode
open SonicPlayer.xcodeproj

# Build via CLI (iPhone simulator)
xcodebuild -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build

# Run the tests
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation

# SPM dependencies resolve automatically on first build
```

`-skipMacroValidation` is required from the CLI: TCA ships a macro, and Xcode gates
unapproved macros behind a GUI trust prompt that `xcodebuild` cannot answer. In the Xcode
app you approve it once instead.

Requires Xcode 27 — `xcode-select -p` must point at the Xcode app, not Command Line Tools.

No CocoaPods or Carthage. All dependencies managed via Swift Package Manager.

## Architecture — and what it deliberately is not

```
View (SwiftUI)  ->  ViewModel (@Observable)  ->  Client (struct of closures)  ->  AVFoundation / FileManager

Domain/   pure decision logic, Foundation only, no framework and no TCA
Models/   plain data types
```

There is **no Repository, no DataSource, no UseCase and no DTO layer**, and that is a decision
rather than an omission. Those layers solve problems this app does not have:

| Layer | Why it is absent |
|---|---|
| Repository / DataSource | They hide *which source answered* — cache vs network. This app has one source: the filesystem. The clients already are that abstraction, substitutable by plain assignment. |
| DTO | Wire formats drift from domain models. There is no wire. The only serialised type is `PlaybackSession`, whose JSON shape is pinned by test because it *is* the on-disk contract. |
| UseCase | They hold orchestration reusable across UIs. There is one UI, and the business rules are pure functions in `Domain/` — wrapping each in a protocol and a class to call one function is ceremony. |

**Depth is decided per feature, not for the app.** A layer is added when a specific condition
makes it necessary, never because a feature feels important:

| Layer | Add it when |
|---|---|
| `Domain/` type | there is a decision statable without UI or I/O — almost always |
| Client | it touches a system framework or the filesystem |
| Repository | **two sources answer the same question** and something must choose between them |
| DTO | an external format exists **that you do not control** |
| UseCase | orchestration spans 2+ clients **and** is called from 2+ places, or must be tested without a view model |

By that test, every feature today is ViewModel + clients + `Domain/`: one source, no wire format.
The StudyHub epics (#7 auth, #8 upload, #9 listening) are the ones that qualify for the full stack —
Keychain and remote both answer "who is signed in", the API JSON is not ours, and a remote course
list with a local cache is the repository case exactly.

Do not retrofit those layers onto the offline features to make the codebase look uniform. Uniformity
is not the goal; each layer paying for itself is.

Known cost of the current shape: orchestration lives in view models. `PlayerViewModel.restoreSession`
is real business logic in the presentation layer. If a view model keeps growing, extract the
orchestration into `Domain/` rather than reaching for the full layered stack.

Note also that this codebase is **async/await throughout**, not Combine.

## Architecture

**TCA (The Composable Architecture)** with strict unidirectional data flow:

- **Features/** - **Mid-migration (#5): TCA reducers are being replaced by `@Observable` view models, one feature at a time.** A feature is therefore either a `{Name}Feature.swift` (reducer, not yet migrated) or a `{Name}ViewModel.swift` (migrated), plus its `{Name}View.swift`. Check which before adding to one. Home is a further exception: no view file, its UI is inlined in `App/AppView.swift`
- **Clients/** - Dependency-injected wrappers around system frameworks (AVFoundation, FileManager)
- **Models/** - Plain data types (`AudioFile`, `FileSystemItem`, `PlaybackSpeed`)
- **Domain/** - Pure decision logic, Foundation only, no TCA. Extracted from reducers so its tests survive the TCA→MVVM migration unchanged (#11). Add logic here rather than inlining it in a reducer.
- **Utilities/** - Shared UI components and helpers
- **App/** - Root `AppFeature` composes all child reducers; `AppView` is a single screen with no tab bar. Player, recording and import are presented as **sheets** over Home; settings is **pushed** via `.navigationDestination` (note the state flag is still named `isSettingsSheetPresented`)

### Feature modules

Migration status per #5. Reducers still compose into `AppFeature`; view models are owned by
`AppView` as `@State`, because `AppFeature.State` is a value type and cannot hold a reference.

| Feature | Type | Status | Purpose |
|---------|------|--------|---------|
| Home | `HomeViewModel` | **migrated** (#16) | Folder suggestions, recently added |
| Files | `CollectionsFeature` | reducer | File/folder browser with navigation stack |
| Player | `PlayerViewModel` | **migrated** (#15) | Playback engine, queue, session persistence |
| Recording | `RecordingFeature` | reducer | Audio capture and trimming |
| Settings | `SettingsViewModel` | **migrated** (#13) | Preferences via UserDefaults |
| Onboarding | `OnboardingViewModel` | **migrated** (#14) | First-launch carousel |

Cross-feature communication out of a migrated feature travels through a **closure wired at the
composition root**, never by reading another feature's state — the shape `willRemoveItems` uses in
`CollectionsFeature` and that #19 generalises. See `AppView.wireViewModels()`.

**`AppFeature.State.commands` runs the other direction and is temporary.** A few reducer cases
still need to reach the player or Home — playing a tapped file needs the queue, which is computed
from `filesRoot.items` and exists only in the store. A reducer cannot call a reference type, so it
appends an `AppCommand` and `AppView` drains the array in `.onChange`, then sends
`.commandsHandled`. #19 turns `AppFeature` into a coordinator that holds the view models directly
and deletes the channel — do not build on it.

### Key patterns
- `@Reducer` macro with `@ObservableState`
- `@Dependency` for all external effects (audio, files, artwork) — in reducers. Migrated view
  models take their clients as **init parameters defaulting to `.live`**; there is no `@Dependency`
  in a view model
- `SessionStore` for session persistence. It replaced `@Shared(.fileStorage(...))` in #15 and
  **writes the same JSON to the same path**, because existing installs have a `session.json` — the
  location and shape are a compatibility boundary, not an implementation detail
- `@AppStorage` for user preferences
- `StackState`/`StackAction` for push navigation
- Manual `Equatable` conformance where needed (e.g., ignoring artwork cache)

## Coding Conventions

- **Swift 5, iOS 18.0+, SwiftUI only** (no UIKit views)
- **TCA patterns**: All state mutations in reducers, all side effects via `Effect`
- **Naming**: Features as `{Name}Feature.swift` / `{Name}View.swift`; clients as `{Name}Client.swift`
- **Colors**: Use `ColorPalette` constants (`sonicPrimary`, `sonicTextPrimary`, etc.) - never hardcode hex
- **Styles**: Reusable button styles and modifiers defined in `Theme.swift`
- **No magic numbers**: Use constants or theme values for spacing/sizing
- **Empty states**: Use `EmptyStateView` for consistent empty state UI
- **Localization**: All user-facing strings must go through `Localizable.xcstrings` (9 languages supported: en, es, fr, ar, zh-Hans, hi, pt, ru, bn)

## Dependencies

- **ComposableArchitecture** v1.26.1 (sole *direct* third-party dependency; it pulls in 13 more)
- All transitive deps (swift-dependencies, swift-sharing, swift-perception, swift-navigation, etc.) are pinned in `Package.resolved` — 14 packages in total, all of which leave with TCA
- Do **not** drop below 1.26: TCA 1.23.1 fails to compile on Xcode 27 (`cannot form key path to main actor-isolated subscript` in `NavigationStack+Observation.swift`, upstream issue #3950)

## File Structure

```
SonicPlayer/
  App/           # Entry point, root reducer, root view, quickstart
  Features/      # Home/, Player/, Files/, Recording/, Settings/
  Clients/       # AudioPlayerClient, AudioRecorderClient, FileManagerClient, ArtworkClient, AudioTrimmerClient
  Models/        # AudioFile, FileSystemItem, PlaybackSpeed
  Domain/        # QueueMath, PathMatching, UniqueNameResolver, SessionCodec, SessionRestorePolicy, RecordingFilename, PlaybackSession
  Utilities/     # ColorPalette, Theme, WaveformView, EmptyStateView, ShareSheet, etc.
  Resources/     # Assets.xcassets, Localizable.xcstrings, Quickstart.json, Info.plist
```

## Testing

`SonicPlayerTests` is a unit-test target with zero third-party dependencies. It is a
file-system-synchronized group, so any `.swift` file dropped into `SonicPlayerTests/` is
compiled automatically — no project edit needed.

Tests use **Swift Testing** (`@Suite`, `@Test`, `#expect`) — never XCTest (#27).

Test reducers with a **non-exhaustive `TestStore`**:

```swift
@Suite(.serialized)          // see the parallelism note below
struct RecordingTests {
    @MainActor
    @Test func savingDismissesTheSheet() async {
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.defaultFileStorage = .inMemory   // only for reducers that still hold @Shared
            $0.fileManager.listItems = { _ in [] }
        }
        store.exhaustivity = .off       // assert one thing, don't match every effect
        await store.send(.recording(.recordingSaved))
        #expect(!store.state.isRecordingSheetPresented)
    }
}
```

Never call `SomeFeature().reduce(into:action:)` directly — it is deprecated as of TCA 1.26,
and it bypasses the store, so effects never run and the assertion covers less than it appears to.

Three differences from XCTest that bite when writing new tests:

- **Suites run in parallel**, across and within. Any suite touching global mutable state —
  `UserDefaults` (which `AppFeature.State()` reads), or the shared `AudioPlayerManager` — needs
  `@Suite(.serialized)`, or must be made genuinely concurrency-safe. A captured `var` written from
  inside a `@Sendable` client closure is a data race; use `Mutex`.
- **`Testing` does not re-export Foundation.** Add `import Foundation` for `URL`, `Date`, `UUID`.
- **`#expect`'s message is `Comment?`, not `String`.** A literal or `"\(interpolation)"` works; a
  bare `String` variable does not.

## Release

Pushing to `main` triggers `.github/workflows/distribute.yml`, which archives, signs and uploads
to TestFlight. **The merge is the release** — there is no separate promotion step.

Before bumping `CFBundleShortVersionString` in `Info.plist`, add a matching section to
`RELEASE_NOTES.md`. The workflow reads the section whose heading equals `## <version>` and ships it
as What's New; with no matching section testers get a placeholder and a build warning.

The runner pins **Xcode 26.3**. Do not lower it: `ComposableArchitecture` and `swift-sharing`
declare `swift-tools-version: 6.1`, so anything below Xcode 16.3 fails during package resolution
with an error that does not mention Xcode. A guard step asserts the Swift version and fails with a
readable message instead.

To prove a pipeline change without shipping, run the workflow manually from the Actions tab with
**dry_run** checked — it archives and exports but skips the upload.

## Git Workflow

- **main** - stable branch
- **feat** - active feature development branch
- PRs from `feat` into `main`
