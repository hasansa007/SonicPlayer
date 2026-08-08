# CLAUDE.md - SonicPlayer

## Project Overview

SonicPlayer is a native iOS audio player app (iOS 18.0+) built with **SwiftUI** and `@Observable` MVVM, with **zero third-party dependencies** (#20). It supports browsing, playing, and recording audio files with a minimalist Sonic teal design.

**Bundle ID:** `com.hasan.sonicplayer`

## Build & Run

```bash
# Open in Xcode
open SonicPlayer.xcodeproj

# Build via CLI (iPhone simulator)
xcodebuild -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run the tests
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

**There are no dependencies to resolve.** `-skipMacroValidation` used to be required here because
TCA shipped a macro and Xcode gates unapproved macros behind a GUI trust prompt `xcodebuild` cannot
answer. No package means no macro, so the flag is gone (#20). If you see it in an older command it
is harmless but pointless.

Requires Xcode 27 — `xcode-select -p` must point at the Xcode app, not Command Line Tools.

No CocoaPods or Carthage. All dependencies managed via Swift Package Manager.

## Architecture — and what it deliberately is not

```
View (SwiftUI)  ->  ViewModel (@Observable)  ->  Client (struct of closures)  ->  AVFoundation / FileManager

Domain/   pure decision logic, Foundation only, no framework and no TCA
Models/   plain data types
```

There is **no DataSource, no UseCase and no DTO layer, and exactly one Repository**, and that is a
decision rather than an omission. Those layers solve problems this app does not have:

| Layer | Why it is absent |
|---|---|
| Repository / DataSource | They hide *which source answered* — cache vs network. This app has one source: the filesystem. The clients already are that abstraction, substitutable by plain assignment. **One exception, taken knowingly: `PlaybackRepository` (#44) — `ARCHITECTURE.md` says why it does not meet the trigger below and was added anyway.** |
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

Known cost of the current shape: orchestration lives in view models. `PlayerViewModel.openFromFiles`
is real business logic in the presentation layer. If a view model keeps growing, extract the
orchestration into `Domain/` rather than reaching for the full layered stack.

`restoreSession` used to be the other example and is now the worked one (#44): the decision went to
`SessionRestorePlan`, the I/O to `PlaybackRepository`, and what stayed is the part that genuinely
coordinates two things. Note what that did **not** buy — the file went 615 lines to 613. Splitting
one method out of a six-concern type makes it testable, not smaller.

`openFromFiles` also shows the limit of that rule. Its I/O half went to `OpenInImport` in
`Features/Files/` rather than `Domain/`, for the same reason the recursive folder import does not
live there: it is security-scoped access and a copy, with no decision left over once those are
removed. **`Domain/` is for logic you can state without I/O, not for everything that is not a
view.** What stayed on the view model is the part that genuinely coordinates two things — the
import and the session restore it has to outrank (#33).

Note also that this codebase is **async/await throughout**, not Combine.

## Architecture

**`ARCHITECTURE.md` is the authority** — the layering, what is deliberately absent, when each layer
earns its place, and the mapping onto a textbook clean-architecture stack. What follows is the
day-to-day version.

**MVVM with `@Observable`, async/await throughout.** There are no reducers and no `Store`: the
TCA→MVVM migration (#5) finished at slice 10 (#19). TCA still ships as a dependency because the
five clients use its `@DependencyClient` macro; #20 removes it.

- **Features/** - one `{Name}ViewModel.swift` + `{Name}View.swift` per feature. A `{Name}Feature.swift` would be a leftover — there are none. Home is an exception: no view file, its UI is inlined in `App/AppView.swift`
- **Clients/** - structs of closures wrapping system frameworks (AVFoundation, FileManager), each with a `.live` and a `.test`
- **Models/** - Plain data types (`AudioFile`, `FileSystemItem`, `PlaybackSpeed`)
- **Domain/** - Pure decision logic, Foundation only. Extracted from reducers so its tests survived the migration unchanged (#11). Add logic here rather than inlining it in a view model.
- **Utilities/** - Shared UI components and helpers
- **App/** - `AppViewModel` is the composition root: it owns every view model and wires every cross-feature edge in its `init`. `AppView` takes it from the environment and owns nothing but its own share sheet. Single screen, no tab bar — player, recording and import are **sheets** over Home; settings is **pushed** via `.navigationDestination`

### Feature modules

| Feature | View model | Purpose |
|---------|------------|---------|
| Home | `HomeViewModel` (#16) | Folder suggestions, recently added |
| Files | `CollectionsViewModel` (#18) | File/folder browser, one model per depth |
| Player | `PlayerViewModel` (#15) | Playback engine, queue, session persistence, open-from-Files |
| Recording | `RecordingViewModel` (#17) | Audio capture, and the editor via `EditRecordingViewModel` |
| Settings | `SettingsViewModel` (#13) | Preferences via UserDefaults |
| Onboarding | `OnboardingViewModel` (#14) | First-launch carousel |

Cross-feature communication travels through a **closure wired at the composition root**, never by
reading another feature's state. `CollectionsViewModel.onWillRemoveItems` is the canonical shape,
and it is that shape for a reason: the items **travel in the call** rather than being read back,
because the selection is cleared before the removal runs (#22). All of it is in
`AppViewModel.wire()`, run once at construction — which is what makes `AppViewModelTests` able to
exercise every edge without a view.

The one edge not in `wire()`: `.onOpenURL` calls `app.openedFromFiles(url)` directly, because the
URL only exists at the call site.

**`AppFeature`, the root `Store` and the `AppCommand` channel are all gone.** If you find a
reference to any of them, it is stale.

**`SonicPlayerApp.app` is `static` for exactly one reason:** `AppDelegate` receives Home-screen
quick actions from UIKit, outside any view, and `@State` cannot be static. Nothing else reads it —
every view gets the coordinator from the environment. It is also a `static let` and therefore lazy,
which is what keeps it uncreated under test; `isRunningTests` in that file depends on this.

### Key patterns
- View models take their clients as **init parameters defaulting to `.live`**. There is no
  dependency-injection framework and no `@Dependency` anywhere outside the clients' own TCA bridge
- `SessionStore` for session persistence. It replaced `@Shared(.fileStorage(...))` in #15 and
  **writes the same JSON to the same path**, because existing installs have a `session.json` — the
  location and shape are a compatibility boundary, not an implementation detail
- **Long-lived work in a view model is an owned `Task`, cancelled in an `isolated deinit`.** There
  is no clock abstraction: `Clock.timer(interval:)` came from swift-clocks via TCA, so a periodic
  loop is a hand-written `Task.sleep`. Extract the **cadence** as a constant and test that; the
  sleep around it is glue and is deliberately untested (#17)
- `@AppStorage` for user preferences
- **`NavigationStack(path:)` over a plain `[URL]`** for push navigation, the path held by
  `AppViewModel`. `StackState`/`StackAction` are gone (#18): each depth below the root is a
  `CollectionsViewModel` owned by its own screen as `@State`, with its callbacks wired at
  construction. The depth that raises an event passes its own data out — which is what removed the
  parent reaching into arbitrary stack depth by element id
- Manual `Equatable` conformance where needed (e.g., ignoring artwork cache)

## Coding Conventions

- **Swift 5, iOS 18.0+, SwiftUI only** (no UIKit views)
- **Naming**: features as `{Name}ViewModel.swift` / `{Name}View.swift`; clients as `{Name}Client.swift`
- **Colors**: Use `ColorPalette` constants (`sonicPrimary`, `sonicTextPrimary`, etc.) - never hardcode hex
- **Styles**: Reusable button styles and modifiers defined in `Theme.swift`
- **No magic numbers**: layout values come from `DesignSystem/Tokens.swift` — `Spacing`, `Radius`,
  `Sizing`, `Elevation` (via `.sonicShadow(_:)`), `Motion`. Run `./scripts/lint-magic-numbers.sh`
  before a PR; it checks the screens the #6 epic has already migrated and each slice appends its
  own files to the list. `--all` shows the whole backlog. Zero dependencies on purpose — no
  SwiftLint (#20)
- **Type**: use SwiftUI's semantic styles (`.title3`, `.subheadline`) **directly**. There is
  deliberately no parallel type scale — see `docs/adr/0002-design-system-foundation.md`.
  `Font.sonic*` exists only for a style-plus-weight role with 2+ consumers, and `DisplayFont`
  only for genuinely fixed sizes, which must be read through `@ScaledMetric`
- **Components before literals**: a repeated control belongs in `DesignSystem/Components/`, but
  **only once it has a second consumer** — a component with one caller is the `AudioPlaying`
  mistake in a new place
- **Empty states**: Use `EmptyStateView` for consistent empty state UI
- **Localization**: All user-facing strings must go through `Localizable.xcstrings` (9 languages supported: en, es, fr, ar, zh-Hans, hi, pt, ru, bn)

## Dependencies

**None.** `Package.resolved` pins zero packages as of #20, which removed ComposableArchitecture
and the 13 transitive packages it pulled in (swift-dependencies, swift-sharing, swift-perception,
swift-navigation, swift-syntax, …).

Adding one back is a decision, not a convenience — the whole of epic #5 was spent getting here.
The clients are structs of closures and the tests need no framework; if something looks like it
needs a package, check `ARCHITECTURE.md` first.

## File Structure

```
SonicPlayer/
  App/           # Entry point, AppViewModel (composition root), AppView, quickstart
  Features/      # Home/, Player/, Files/, Recording/, Settings/
  Clients/       # AudioPlayerClient, AudioRecorderClient, FileManagerClient, ArtworkClient, AudioTrimmerClient
                 #   + AudioPlaying / FileManaging — protocols the first two conform to (#44)
  Models/        # AudioFile, FileSystemItem, PlaybackSpeed
  Domain/        # QueueMath, PathMatching, UniqueNameResolver, SessionCodec, SessionRestorePolicy, SessionRestorePlan, RecordingFilename, PlaybackSession, ScrubClamp, SelectionSet, ImportFilter, QuickAction
  Utilities/     # ColorPalette, Theme, WaveformView, EmptyStateView, ShareSheet, etc.
  Resources/     # Assets.xcassets, Localizable.xcstrings, Quickstart.json, Info.plist
```

## Testing

`SonicPlayerTests` is a unit-test target with zero third-party dependencies. It is a
file-system-synchronized group, so any `.swift` file dropped into `SonicPlayerTests/` is
compiled automatically — no project edit needed.

Tests use **Swift Testing** (`@Suite`, `@Test`, `#expect`) — never XCTest (#27).

**There is one style, because there is one shape.** Every feature is a plain object — no
`TestStore`, no `withDependencies`, no `import ComposableArchitecture` anywhere in the target. Pass
`.test` clients to the initialiser:

```swift
@Suite(.serialized)
struct RecordingSaveDismissTests {
    @MainActor
    @Test func savingReportsFinished() async {
        let model = RecordingViewModel(audioRecorder: .test, audioPlayer: player, fileManager: .test)
        await withCheckedContinuation { continuation in
            model.onFinished = { continuation.resume() }
            model.saveRecording()
        }
        #expect(!model.isSaveFlowPresented)
    }
}
```

`await withCheckedContinuation` around a callback beats sleeping for a fixed interval: it waits
exactly as long as the work takes, and a call that never arrives hangs the test rather than passing
it. Note `.test` clients leave every closure without an explicit default **unimplemented** — calling
one reports a failure, so stub the ones the path under test actually reaches.

**Cross-feature behaviour is tested through `AppViewModel`**, which owns the wiring. Build one with
`.test` children and call the closure the source feature would have called:

```swift
let app = makeApp()
app.player.currentTrack = audioFile(at: url)

app.filesRoot.onWillRemoveItems([.file(audioFile(at: url))])   // what the browser raises

#expect(app.player.currentTrack == nil)
```

This is what owning the children buys (#19): under the old shape the same edges lived in
`AppView.wireViewModels()` and were reachable only by rendering a view.

Anything about `TestStore`, `withDependencies`, `$0.defaultFileStorage` or
`SomeFeature().reduce(into:action:)` in an older note is **dead** — there are no reducers left.

Three differences from XCTest that bite when writing new tests:

- **Suites run in parallel**, across and within. Any suite touching global mutable state —
  `UserDefaults` (which `SettingsViewModel` and `OnboardingViewModel` read), or the shared
  `AudioPlayerManager` — needs
  `@Suite(.serialized)`, or must be made genuinely concurrency-safe. A captured `var` written from
  inside a `@Sendable` client closure is a data race; use `Mutex`.
- **`Testing` does not re-export Foundation.** Add `import Foundation` for `URL`, `Date`, `UUID`.
- **`#expect`'s message is `Comment?`, not `String`.** A literal or `"\(interpolation)"` works; a
  bare `String` variable does not.

## Release

Summarised here for context; **`docs/deploy-and-staging.md` is authoritative** and wins if these
two ever disagree.

Pushing to `main` triggers `.github/workflows/distribute.yml`, which archives, signs and uploads
to TestFlight. **The merge is the release** — there is no separate promotion step.

Before bumping `CFBundleShortVersionString` in `Info.plist`, add a matching section to
`RELEASE_NOTES.md`. The workflow reads the section whose heading equals `## <version>` and ships it
as What's New; with no matching section testers get a placeholder and a build warning.

The runner pins **Xcode 26.3**, and the guard step asserts the toolchain can build the project.

**The original reason for the pin is gone**: it was that `ComposableArchitecture` and
`swift-sharing` declared `swift-tools-version: 6.1`, so anything below Xcode 16.3 failed during
package resolution with an error that never mentioned Xcode. There are no packages now (#20), so
that failure mode cannot occur. The pin stays because 26.3 is the newest available on `macos-15`
and the closest to the local toolchain — not because of a package constraint. Do not re-derive the
old reason from an older copy of this paragraph.

To prove a pipeline change without shipping, run the workflow manually from the Actions tab with
**dry_run** checked — it archives and exports but skips the upload.

## Git Workflow

**`docs/deploy-and-staging.md` is the authority — read it before merging anything.**

- **`gh-<issue>-<slug>`** — feature branches. PR into `feat`, never into `main`
- **`feat`** — **pre prod**. Integrated but not shipped
- **`main`** — **prod**. Pushing here uploads to TestFlight; the merge *is* the release

`feat` is a pre-prod branch with a feature-branch name, so tooling that guesses the branch model
from names (`staging` → `develop` → `main`) resolves pre prod to `main` — the branch that ships.
The runbook exists to outrank that guess.
