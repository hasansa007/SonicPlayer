# PROJECT_MAP

A navigation aid, created on slice 1 of epic #6 (#47). `ARCHITECTURE.md` says *why* the code is
shaped this way and wins on any conflict; this file says *where things are* and *what is not
wired up*.

**Version 2.3.0 (build 21) · iOS 18.0+ · zero third-party dependencies**

---

## TECH_STACK

| | |
|---|---|
| Language | Swift 5, async/await throughout — **no Combine anywhere** |
| UI | SwiftUI only. No UIKit views; three `UIViewRepresentable` bridges (`VolumeView`, `ShareSheet`, waveform capture) |
| State | `@Observable` MVVM. No reducers, no `Store` — TCA removed in #20 |
| Persistence | `UserDefaults` (`@AppStorage`) for preferences; `SessionStore` → `session.json` for playback session |
| Media | AVFoundation, MediaPlayer (lock screen / remote commands) |
| Tests | Swift Testing (`@Suite`/`@Test`/`#expect`) — **never XCTest** (#27). 22 files, 181 cases |
| Dependencies | **None.** `Package.resolved` pins zero packages |
| Localization | `Localizable.xcstrings`, 144 keys × 9 languages (en, es, fr, ar, zh-Hans, hi, pt, ru, bn) |
| Design system | `DesignSystem/Tokens.swift` + `Typography.swift` + `Components/` (#47). `ColorPalette`/`Theme` stay in `Utilities/` — ADR 0002 |

Xcode 27 locally; the release runner pins 26.3. See `docs/deploy-and-staging.md`.

---

## SYSTEM_FLOW

```
SonicPlayerApp                    static `app` — AppDelegate needs it for quick actions
  └── AppViewModel                composition root: owns every view model, wires every edge
        ├── HomeViewModel         suggestions, recently added
        ├── CollectionsViewModel  browser — one instance per navigation depth
        ├── PlayerViewModel       playback, queue, session, open-from-Files
        ├── RecordingViewModel    capture (+ EditRecordingViewModel for trimming)
        ├── SettingsViewModel     preferences
        └── OnboardingViewModel   first-launch carousel
```

**One screen.** Home is the app; player / recording / import are **sheets**, settings is
**pushed** via `.navigationDestination` over a plain `[URL]` path. No tab bar — see
`docs/adr/0001-navigation-stays-single-screen.md`.

**Cross-feature edges travel through closures wired once in `AppViewModel.wire()`**, never by
reading another feature's state. The one exception is `.onOpenURL`, which calls
`app.openedFromFiles(url)` directly because the URL only exists at the call site.

### Layers, and where each lives

| Layer | Directory | Count |
|---|---|---|
| Views | `Features/*/`, `App/` | 10 |
| View models | `Features/*/`, `App/` | 8 |
| Clients (structs of closures, `.live` + `.test`) | `Clients/` | 5 + 2 protocols |
| Pure decision logic (Foundation only) | `Domain/` | 17 |
| Plain data | `Models/` | 3 |
| Design system | `DesignSystem/`, `DesignSystem/Components/` | 2 + 4 |
| Legacy shared UI | `Utilities/` | 10 |

### A track, from tap to sound

```
CollectionsView tap
  → CollectionsViewModel.select
  → (closure wired in AppViewModel)
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
| `Utilities/ShareSheet.swift` | **Zero references.** A `UIActivityViewController` bridge nothing presents. `AppView` was documented as owning a share sheet; it no longer does |
| `Utilities/SwipeToDelete.swift` | **Zero references.** `SwipeToDeleteRow` — the browser uses the system swipe actions instead |

Both survive #48. The browser uses SwiftUI's own `.swipeActions`, and neither is reachable from
any screen this epic has touched — deleting them belongs to whoever owns sharing, not to a
restructure passing through.

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
| #49 | Recording + editor | not started. Largest surface (915 lines) |
| #50 | Settings / About / Help | not started |
| #51 | Home | not started. Removes the last inline layout, from `App/AppView.swift` |

`EmptyStateView` stays and is **improved rather than replaced**: #47 changed its `title`/`message`
to `LocalizedStringKey`, because `Text(String)` binds to the non-localizing overload and every
empty state in the app was rendering English in all nine languages. No caller had to change —
they all pass literals.

### Known gaps

| Gap | Where |
|---|---|
| No UI tests, and RTL is where that bites | The 181 tests are unit tests; no screen is asserted on. Two RTL "bugs" (#54, #63) were filed on plausible reasoning and **both were false** — settled only by rendering on a device and measuring. SwiftUI mirrors `.offset(x:)` but **not** gesture `location.x`; the two look alike and behave oppositely. Numbers are in `ScrollingText` and `ScrubGeometry`'s doc comments. Any future RTL claim should be measured before it is filed |
| Player does not fit at AX5 | **#55** — the portrait layout does not scroll |
| Lint gate is advisory and scoped | `scripts/lint-magic-numbers.sh` checks only migrated screens; `--all` reports 298 literals still outstanding. Not in CI |
| Nothing enforces the layering | No module boundary, no build-time check. The discipline is review and `ARCHITECTURE.md` |
| `listItems` has no test | `FileManagerClient.live` is a `static let` with a hardcoded documents directory, so nothing can reach it. #41's staging filter is tested as a `Domain/` predicate; that the client *calls* it is unasserted |
| `main` carries a commit `feat` does not | `c7e508e`, from 2026-04-11. `feat` → `main` will not fast-forward |
