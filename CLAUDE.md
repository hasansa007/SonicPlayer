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

Requires **Xcode 26.6** — `xcode-select -p` must point at the Xcode app, not Command Line Tools.

This said "Xcode 27" and no such release exists: 27 is at beta 5 as of August 2026, and the local
toolchain is 26.6 (17F113). A requirement naming a version nobody can install reads as "you are on
the wrong Xcode" to whoever checks. **26.6 is also the floor the App Store currently accepts** —
see the Release section, where being below it is what got 3.0.0 build 23 rejected.

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
- **App/** - `AppViewModel` is the composition root: it owns every view model and wires every cross-feature edge in its `init`. `AppView` takes it from the environment and owns nothing but its own share sheet

### The dial is the app (#6)

**There are no screens beside the dial**, with two named exceptions below. Player, Files, Settings,
Recording and Edit each had a view, each reachable only from a shell the dial replaced, and all five
are gone along with the sheets and pushes that presented them.

**That sentence was false for four months and this paragraph is the correction (#76).** It was
written when the deletion was *intended*; `ShellView`, `ShellViewModel`, `PlayerView`,
`MiniPlayerView` and `SettingsView` in fact stayed in the tree, compiled into every build, and
unreachable. Three issues were later closed as "unreachable, not fixed" — #55, #57, #77 — because
their defects were still in those files. A doc that describes an intention in the present tense is
worse than one that says nothing, because the next reader greps and believes it.

**The two exceptions are real and live:** `AboutView` and `HelpView` are conventional screens,
presented as sheets from `AppView` and reached from the dial's Settings rows. They are the last two,
and #50 owns restructuring them.

What is left is one view rendering one value:

```
DialCommand  ->  DialNavigator (pure state machine)  ->  DialScreen (a value)  ->  DialScreenView
                        |
                    DialEffect  ->  DialViewModel  ->  the feature view models below
```

`DialScreen` is what makes the eight screens *data*: adding a ninth is a value, not a file, and the
navigator is built and tested with no SwiftUI in sight. Anything the user can do is a `DialCommand`
— a turn, a press, a hold, a nudge, or an `action(id:)` from a chip — and anything the app must
*do* about it leaves as a `DialEffect`, which is where the view models below are still reached.

**Every control drawn on the card is a stop on the wheel.** `DialNavigator.chipIDs` is the one list
the ring walks and the projection draws, so a control cannot be added to the row and be unreachable
by the only input surface the app has. That defect shipped three times before the list was unified.

### Feature modules

The view models survive as the layer that touches AVFoundation and the filesystem. **Their views do
not** — the dial presents none of them, so state that lived only in a deleted view was silently
dead until it was moved.

| Feature | View model | Purpose |
|---------|------------|---------|
| Dial | `DialViewModel` (#6) | Holds the navigator, applies its effects, and is the only view model with a view |
| Home | `HomeViewModel` (#16) | The library the dial lists — `allFiles` and the folder tree |
| Files | `CollectionsViewModel` (#18) | Rename, delete, create and move, reached through `AppViewModel` |
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
  Features/      # Dial/ — the only one with a view. Home/, Player/, Files/, Recording/, Settings/
  Clients/       # AudioPlayerClient, AudioRecorderClient, FileManagerClient, ArtworkClient, AudioTrimmerClient
                 #   + AudioPlaying / FileManaging — protocols the first two conform to (#44)
  Models/        # AudioFile, FileSystemItem, PlaybackSpeed
  DesignSystem/  # Tokens (Spacing, Radius, Sizing, Elevation, Motion), DialRing, LiveHues
  Domain/        # The dial: DialNavigator + DialNavigatorScreen, DialScreen, DialCommand, DialEffect,
                 #   DialRoute, DialSort, DialContent, MoveDestinations, DialTrimRange
                 # And the rest: QueueMath, PathMatching, UniqueNameResolver, SessionCodec,
                 #   SessionRestorePolicy, SessionRestorePlan, RecordingFilename, PlaybackSession,
                 #   ScrubClamp, SelectionSet, ImportFilter, QuickAction
  Utilities/     # ColorPalette, Theme, WaveformView, EmptyStateView, ShareSheet, etc.
  Resources/     # Assets.xcassets, Localizable.xcstrings, Quickstart.json, Info.plist

SonicPlayerShare/  # The share extension (#112) — a SEPARATE TARGET, not part of the app's
                   #   synchronized group. ShareViewController + its own Info.plist and
                   #   entitlements. Deliberately thin: it cannot see Documents/ and decides
                   #   nothing, because the system kills it without notice
```

**There are three targets now, not two.** `SonicPlayerShare` is an app extension embedded in the
app bundle's `PlugIns/`, sharing `group.com.hasan.sonicplayer` with it. The app and the extension
are separate processes with separate containers — the group is the only thing they share, and it is
a queue the extension writes and the app drains, never shared storage. See
`docs/superpowers/specs/2026-08-14-share-import-design.md`.

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

## App Store compliance — binding on the UI and on every word that ships

The dial is a rotary control, and rotary controls on a music player invite one comparison in
particular. App Store Review Guideline 5.2.5 prohibits an app that "appears confusingly similar to
an existing Apple product, interface…", and *Rewound* was removed in 2020 for exactly that. Two
standing rules follow, and **`docs/superpowers/specs/2026-08-09-rotary-shell-design.md` §3 is the
authority** — it holds the full table of what is kept and what is deliberately changed.

- **No skeuomorphic mimicry of Apple hardware.** Flat and matte, the app's dark palette and its
  gradients. Never a white or grey plastic wheel, a chrome bevel, brushed metal or gloss.
- **Five words never appear** in the UI, store copy, `RELEASE_NOTES.md`, App Store keyword metadata,
  screenshots, type names or commit messages: *iPod*, *Click Wheel*, *Classic Player*, *Retro*,
  *Nostalgia*. The first two are Apple trademarks; the other three are refused because they are the
  words that argue an app is trading on a resemblance, which is evidence for the reading 5.2.5
  turns on.
- **Positioning is affirmative:** *precision dial navigation* and *gesture-based scrubbing*, for
  modern use. A claim about what the control does, not about what it recalls.

`RELEASE_NOTES.md` is the surface most likely to slip, because a version's What's New is written in
a hurry and ships straight to testers.

## Release

Summarised here for context; **`docs/deploy-and-staging.md` is authoritative** and wins if these
two ever disagree.

Pushing to `main` triggers `.github/workflows/distribute.yml`, which archives, signs and uploads
to TestFlight. **For testers, the merge is the release** — there is no promotion step.

**Reaching the public App Store is manual and nothing here does it.** SonicPlayer 3.0.0 (25) has
been live on the App Store since 2026-08-13; that submission was made by hand in App Store Connect.
This paragraph used to end at "the merge is the release", which was true only while the app was
TestFlight-only, and it is the sentence most likely to mislead you into thinking a merge reached
users. It reaches testers. Three things follow:

- **What's New is two different fields.** The workflow writes the *TestFlight build's*. The App
  Store version's is per-language and lives in `docs/appstore/<version>/` — see its README.
- **Tag the shipped commit** once a release is live, bare version, no `v` prefix. A tag push does
  not trigger the workflow (`push: branches: [main]`).
- **Guideline 5.2.5 is now removal risk, not rejection risk.** See the compliance section above;
  the rules are unchanged, the price of breaking them is not.

Before bumping `CFBundleShortVersionString` in `Info.plist`, add a matching section to
`RELEASE_NOTES.md`. The workflow reads the section whose heading equals `## <version>` and ships it
as What's New; **with no matching section the run fails before the archive.** It used to ship a
placeholder and log a warning, which is the quiet-failure shape that guard exists to remove.

**The version lives in `SonicPlayer/Info.plist` and nowhere else.** The app target sets
`GENERATE_INFOPLIST_FILE = NO`, so the plist's literal values ship and every workflow step reads
them with `PlistBuddy`. The target used to *also* carry `MARKETING_VERSION = 2.3.0` and
`CURRENT_PROJECT_VERSION = 16` — read by nothing, four versions stale, and exactly what Xcode's
General tab writes when you bump a version in the UI. They are deleted, and a guard step now fails
the run if either reappears disagreeing with the plist.

**"And nowhere else" acquired an exception with the share extension (#112), and it is checked
rather than trusted.** `SonicPlayerShare/Info.plist` carries its own
`CFBundleShortVersionString` and `CFBundleVersion`, because an embedded extension has to, and
App Store Connect **rejects an upload where they disagree with the host app's**. No build setting
removes the duplication — `$(MARKETING_VERSION)` is precisely the key the paragraph above exists to
keep deleted. So the same guard step now also asserts the extension's two keys equal the app's, and
applies the stale-build-setting rule to the extension target as well. **Bump a version and you must
edit both plists.** The guard is what stops that being discovered after an upload, against a build
number that can never be reused.

The runner is `macos-26` and pins **Xcode 26.6**. The guard step asserts **two** floors, and the
distinction is the whole point of it: one that the toolchain can *compile* this project, and one
that Apple will *accept the upload*.

**The Xcode pin has been wrong twice, for opposite reasons, and both are worth knowing.** First it
was 16.2, too old to resolve `swift-tools-version: 6.1` packages — a real constraint that #20
deleted along with the packages. It was then raised to 26.3 and justified as "newest on `macos-15`,
closest to the local toolchain", which was accurate and still shipped a build Apple refused: 3.0.0
build 23 archived, signed and uploaded cleanly and was rejected by automated validation with
**ITMS-90111, unsupported SDK**.

So the pin is not a free choice between versions that compile. **Apple sets a moving floor on the
SDK, and an Xcode below it fails only after the upload**, against a build number that can never be
reused. `macos-15` carries nothing above 26.3, which is why the image moved too. When Apple raises
the floor again — watch `developer.apple.com/news/releases` — raise `REQUIRED_XCODE` in the guard,
the `xcode-select` path, and the image if it has nothing newer.

Do not re-derive the package-resolution reason, or the "newest available on the image" reason, from
an older copy of this paragraph. The first is extinct and the second is what caused a rejection.

To prove a pipeline change without shipping, run the workflow manually from the Actions tab with
**dry_run** checked — it archives and exports but skips the upload.

## Git Workflow

**`docs/deploy-and-staging.md` is the authority — read it before merging anything.**

- **`gh-<issue>-<slug>`** — feature branches. PR into `feat`, never into `main`
- **`feat`** — **pre prod**. Integrated but not shipped
- **`main`** — **prod**. Pushing here uploads to TestFlight; the merge is the release *for testers*.
  The public App Store submission is a separate manual step — see Release above

`feat` is a pre-prod branch with a feature-branch name, so tooling that guesses the branch model
from names (`staging` → `develop` → `main`) resolves pre prod to `main` — the branch that ships.
The runbook exists to outrank that guess.
