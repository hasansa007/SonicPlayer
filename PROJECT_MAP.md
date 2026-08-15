# PROJECT_MAP

A navigation aid, created on slice 1 of epic #6 (#47). `ARCHITECTURE.md` says *why* the code is
shaped this way and wins on any conflict; this file says *where things are* and *what is not
wired up*.

**Version 3.0.0 (build 26) · iOS 18.0+ · zero third-party dependencies**

**Build 26 is unreleased; build 25 is what is live on the App Store**, since 2026-08-13. The bump
happened on `gh-112-share-import` because 25 had already been uploaded, and the version guard cannot
see that — it compares the app and extension plists to each other, so a stale pair that agrees sails
through and App Store Connect refuses the upload afterwards. **Both plists move together or the
upload is rejected**; see `docs/deploy-and-staging.md` → *Before bumping the version*.

Read the version from `SonicPlayer/Info.plist`, never from here — this line is a convenience and it
has been wrong before.

---

## TECH_STACK

| | |
|---|---|
| Language | Swift 5, async/await throughout — **no Combine anywhere** |
| UI | SwiftUI only. No UIKit views; three `UIViewRepresentable` bridges (`VolumeView`, `ShareSheet`, waveform capture) |
| State | `@Observable` MVVM. No reducers, no `Store` — TCA removed in #20 |
| Persistence | `UserDefaults` (`@AppStorage`) for preferences; `SessionStore` → `session.json` for playback session |
| Media | AVFoundation, MediaPlayer (lock screen / remote commands) |
| Tests | Swift Testing (`@Suite`/`@Test`/`#expect`) — **never XCTest** (#27). 58 files, 493 cases |
| Dependencies | **None.** `Package.resolved` pins zero packages |
| Targets | **Three** — `SonicPlayer` (app), `SonicPlayerShare` (share extension, #112), `SonicPlayerTests`. The extension is embedded in `PlugIns/` and shares `group.com.hasan.sonicplayer` |
| Localization | `Localizable.xcstrings`, 177 keys × 9 languages (en, es, fr, ar, zh-Hans, hi, pt, ru, bn) |
| Design system | `DesignSystem/Tokens.swift` + `Typography.swift` + `Components/` (#47). `ColorPalette`/`Theme` stay in `Utilities/` — ADR 0002 |

**Xcode 26.6, locally and on the runner** — `REQUIRED_XCODE=26.6` in `distribute.yml`, asserted by a
guard step. This line previously read *"Xcode 27 locally; the release runner pins 26.3"*, and both
halves were wrong in ways that matter: there is no Xcode 27 release to be on, and 26.3 is the pin
that shipped 3.0.0 build 23 into an **ITMS-90111 unsupported-SDK rejection**, burning that build
number. See `docs/deploy-and-staging.md`, which is authoritative.

---

## SYSTEM_FLOW

```
SonicPlayerApp                    static `app` — AppDelegate needs it for quick actions
  └── AppViewModel                composition root: owns every view model, wires every edge
        ├── DialViewModel         the navigator, its effects — the ONLY child with a view
        ├── HomeViewModel         the library the dial lists — allFiles and the folder tree
        ├── CollectionsViewModel  `filesRoot` — rename, delete, create, move
        ├── PlayerViewModel       playback, queue, session, open-from-Files
        ├── RecordingViewModel    capture (+ EditRecordingViewModel for trimming)
        ├── SettingsViewModel     preferences
        └── OnboardingViewModel   first-launch carousel — optional, nil after onboarding
```

**The dial is the app (#6).** This section previously described Home as the app with player,
recording and import as **sheets** and settings **pushed** over a `[URL]` path. That was the
pre-dial architecture and none of it is true: `ShellView`, `PlayerView`, `MiniPlayerView` and
`SettingsView` are all gone from the tree, and the only views left are `AppView`, `OnboardingView`,
the six under `Features/Dial/`, and two shared components in `Utilities/`.

What renders is one view over one value:

```
DialCommand → DialNavigator (pure state machine) → DialScreen (a value) → DialScreenView
                    │
                DialEffect → DialViewModel → the feature view models above
```

Two sheets survive in `AppView` and they are the exceptions, not the pattern: the outbound share
(`ActivityView`, on `app.shareItem`) and the Files import picker (`DocumentPicker`). About and How
it works became dial screens in #50.

See `docs/adr/0001-navigation-stays-single-screen.md`.

**Cross-feature edges travel through closures wired once in `AppViewModel.wire()`**, never by
reading another feature's state. The one exception is `.onOpenURL`, which calls
`app.openedFromFiles(url)` directly because the URL only exists at the call site.

### Layers, and where each lives

| Layer | Directory | Count |
|---|---|---|
| Views | `Features/Dial/`, `App/` | 8 — `AppView`, `OnboardingView`, six `Dial*View` |
| View models | `Features/*/`, `App/` | 9 |
| Clients (structs of closures, `.live` + `.test`) | `Clients/` | 6 + 2 protocols + `ClientErrors` |
| Pure decision logic (Foundation only) | `Domain/` | 38 |
| Plain data | `Models/` | 3 |
| Design system | `DesignSystem/`, `DesignSystem/Components/` | 2 + 2 |
| Legacy shared UI | `Utilities/` | 10 — incl. `EmptyStateView`, `WaveformView` |

Counts verified against the tree 2026-08-15. Every one of them except Models and Utilities had
drifted; `Domain/` was recorded as 17 and is 38, which is the drift most likely to make a reader
believe a decision has nowhere to live.

### A track, from tap to sound

```
DialScreenView press on a row
  → DialCommand.press
  → DialNavigator                    pure — produces DialEffect.play(itemID:queue:)
  → DialViewModel applies the effect
  → PlayerViewModel.loadTrack        sets currentTrack + isLoadingTrack, resolves queue via QueueMath
  → AudioPlayerClient.play           → AudioPlayerManager → AVPlayer
  → trackLoaded()                    isLoadingTrack = false, starts the time observer
  → SessionStore.save                session.json, so the next launch resumes
```

### Session restore, on launch

```
AppView.onAppear → PlayerViewModel.restoreSession
  → PlaybackRepository.restore       which files still exist (the only Repository in the app)
  → SessionRestorePlan.resolve       pure: what to play, which queue, which index
  → sessionLoaded / clearSession
```

An explicit `.onOpenURL` open **outranks** a restore that lands later — claimed synchronously
before any `await` (#33).

---

## ORPHANS & PENDING

Things that exist and are not wired up. Recorded rather than deleted, because each is a decision
somebody has to make.

### Unreferenced code

| File | State |
|---|---|
| `Utilities/SwipeToDelete.swift` | **Zero references.** `SwipeToDeleteRow` — the browser uses the system swipe actions instead |

**`Utilities/ShareSheet.swift` was listed here as a zero-reference orphan and is not one.** Its two
types are both live: `ShareItem` at `App/AppViewModel.swift:45` and `:538`, `ActivityView` at
`App/AppView.swift:58`, presented by `.sheet(item: $app.shareItem)`. The entry survived because the
file is named for a type it does not contain — a grep for `ShareSheet` finds nothing, which reads as
*orphaned* rather than as *misnamed*. Anyone re-checking should grep the type names.

`SwipeToDeleteRow` genuinely has no caller outside its own file, and survives #48 because the
browser uses SwiftUI's own `.swipeActions`.

**`Features/Files/FileItemRow.swift` was deleted in #48** — 111 lines, a 56pt tile, a chevron and
a press animation, and **zero consumers**. It was the file #48 was scoped to extract the shared
Row *from*; nothing had called it in a long time. `MediaFileRowView` was absorbed into `SonicRow`
in the same slice.

### Declared but unconsumed

| Thing | State |
|---|---|
| `AudioPlaying` protocol | No caller. Declared in #44 alongside `FileManaging`; waits for #7 / #9. `ARCHITECTURE.md` names it as the first thing to delete if those never arrive |
| 11 fixed `.system(size:)` values | Five in `RecordingView`, three in `OnboardingView`, one each in `AboutView`, `CollectionsSection`, `AppView`. None scales under Dynamic Type. Slices #49–#51 own them; the player's went in #47 and the collection card's in #48 |
| `ColorPalette` / `Theme` outside `DesignSystem/` | Deliberate deferral, ADR 0002. Revisit at epic end |
| `FileManaging` — 8 of 9 members | Only `metadata(for:)` has a caller (`LivePlaybackRepository`). The rest are exercised by `ClientProtocolConformanceTests` and nothing else |

### The share extension ships and does nothing (#112)

`SonicPlayerShare` is in the bundle, registered with the system, and offered in the share sheet for
audio — and **it imports nothing**. Tapping it shows a stub and cancels the request. This is slice 1
of #112 deliberately: a new target changes what CI archives, signs and uploads, and that is the only
cost in the epic that cannot be undone, so it ships empty and gets proven before any feature code
depends on it.

| Declared | State |
|---|---|
| `group.com.hasan.sonicplayer` App Group | On both targets' entitlements. **Nothing reads or writes it yet**, and it does not exist in the developer portal — unproven against a real signed archive |
| `ShareViewController` | A stub. No queue, no picker, no library access |

Still intent, not code — slices 2–5 in `docs/superpowers/specs/2026-08-14-share-import-design.md` §11:
`folders.json`, the batch manifest and its atomic-rename commit, `InboxDrain`, `ImportInbox`, the
folder picker, the exception screen, and localisation across the nine languages.

**One existing test will need narrowing at slice 2.** `AppViewModelTests.test_becomingActiveOrInactive_neverDrains()`
asserts that nothing drains on `.active`. That is true of the *staging* drain and is ADR 0003's rule;
the group-inbox drain lands on `.active` by design (ADR 0004), so the test's name will over-claim
once it does.

### Resolved by #41 — iOS's staging directory

`OpenInImport` consumes what iOS stages rather than copying out of it, so `Documents/Inbox` stays
empty from here, and `AppViewModel.scenePhaseChanged` empties it wholesale on `.background` to
clear what installs predating #41 still hold. `listItems` filters the directory out of the browser.

**"Already imported" now means the same BYTES, not the same name** — `FileManager.contentsEqual`
against the same-named candidate, with a differing file landing beside it as `Track 2.m4a` via
`UniqueNameResolver`. The name heuristic was wrong in both directions: it missed the same file
re-opened (iOS had renamed it in staging, which *is* #41) and swallowed a different file that shared
a name. This supersedes the behaviour #33 preserved as out of scope.

Three constraints that are easy to undo by accident, all in ADR 0003: the drain runs on
**`.background`** because a launch-time one races `.onOpenURL`; it is **synchronous** because a
`Task` does not run before the app suspends — measured, it landed on the next foreground instead;
and it **skips while `player.isImporting`**, because the import runs detached and can still be
moving a file out of that directory.

### Pending in this epic

| Slice | Screen | State |
|---|---|---|
| #47 | Player + foundation | **merged** (PR #56) |
| #48 | Files / Collections | **merged** (PR #58) — `SonicRow` built, with the browser, Home's recent list and the player's queue as its three consumers |
| #49 | Recording + editor | **merged** — was the largest surface (915 lines) |
| #50 | About / How it works | **merged** — both became dial screens; the last two conventional screens are gone |
| #51 | Home | **merged** — removed the last inline layout from `App/AppView.swift` |

**Epic #6 is complete.** All five slices are closed. This table listed #49–#51 as *not started*
long after they had shipped, which is what let the SYSTEM_FLOW section above go on describing a
pre-dial app that no longer existed.

`EmptyStateView` stays and is **improved rather than replaced**: #47 changed its `title`/`message`
to `LocalizedStringKey`, because `Text(String)` binds to the non-localizing overload and every
empty state in the app was rendering English in all nine languages. No caller had to change —
they all pass literals.

### Known gaps

| Gap | Where |
|---|---|
| No UI tests, and RTL is where that bites | The 181 tests are unit tests; no screen is asserted on. Two RTL "bugs" (#54, #63) were filed on plausible reasoning and **both were false** — settled only by rendering on a device and measuring. SwiftUI mirrors `.offset(x:)` but **not** gesture `location.x`; the two look alike and behave oppositely. Numbers are in `ScrollingText` and `ScrubGeometry`'s doc comments. Any future RTL claim should be measured before it is filed |
| Lint gate is advisory | `scripts/lint-magic-numbers.sh` — `--all` now reports **1** outstanding literal, down from the 298 recorded here. Still not in CI, so it only runs when someone remembers |
| The version guard cannot see what is already uploaded | **#115** — it asserts the app and extension plists agree with **each other**. Two stale-but-equal values pass, and the rejection lands after the upload. `RELEASE_NOTES.md`'s `grep -qx "## $VERSION"` passes for the same reason. Closing it means moving the existing `/v1/builds` query before the archive — see `docs/deploy-and-staging.md` |
| Every release run burns a development certificate | **#114** — a fresh runner has no keychain, so `-allowProvisioningUpdates` creates a certificate rather than fetching one, and Apple caps them at 12. Ten `Created via API` certificates were revoked on 2026-08-15 to unblock #112; the account sits at 3, which is roughly ten runs of headroom. Nothing fails until it does |
| The app bundle ships `settings.local.json` | `SonicPlayer/.claude/settings.local.json` is swept into `SonicPlayer.app/` by the target's synchronized file group — verified in the built bundle. Untracked, so CI does not ship it, but any non-source file dropped under `SonicPlayer/` or `SonicPlayerShare/` lands in the signed product. `membershipExceptions` is the mechanism that excludes them; only `Info.plist` uses it today |
| Nothing enforces the layering | No module boundary, no build-time check. The discipline is review and `ARCHITECTURE.md` |
| `listItems` has no test | `FileManagerClient.live` is a `static let` with a hardcoded documents directory, so nothing can reach it. #41's staging filter is tested as a `Domain/` predicate; that the client *calls* it is unasserted |
| `main` carries commits `feat` does not | **Five**, not the one recorded here: `c7e508e` from 2026-04-11, plus the four `feat` → `main` merge commits (`bf64577`, `3c21233`, `040fa2d`, `fcc5595`). The merge commits are normal for this flow; `c7e508e` is the one that is genuinely only on prod. `feat` → `main` will not fast-forward |
