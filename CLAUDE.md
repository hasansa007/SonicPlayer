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

## Architecture

**TCA (The Composable Architecture)** with strict unidirectional data flow:

- **Features/** - Each feature has a `{Name}Feature.swift` (reducer) and `{Name}View.swift` (UI). Home is the exception: it has no view file, its UI is inlined in `App/AppView.swift`
- **Clients/** - Dependency-injected wrappers around system frameworks (AVFoundation, FileManager)
- **Models/** - Plain data types (`AudioFile`, `FileSystemItem`, `PlaybackSpeed`)
- **Domain/** - Pure decision logic, Foundation only, no TCA. Extracted from reducers so its tests survive the TCA→MVVM migration unchanged (#11). Add logic here rather than inlining it in a reducer.
- **Utilities/** - Shared UI components and helpers
- **App/** - Root `AppFeature` composes all child reducers; `AppView` is a single screen with no tab bar. Player, recording and import are presented as **sheets** over Home; settings is **pushed** via `.navigationDestination` (note the state flag is still named `isSettingsSheetPresented`)

### Feature modules
| Feature | Reducer | Purpose |
|---------|---------|---------|
| Home | `HomeFeature` | Folder suggestions, recently added |
| Files | `CollectionsFeature` | File/folder browser with navigation stack |
| Player | `PlayerFeature` | Playback engine, queue, session persistence |
| Recording | `RecordingFeature` | Audio capture and trimming |
| Settings | `SettingsFeature` | Preferences via UserDefaults |

### Key patterns
- `@Reducer` macro with `@ObservableState`
- `@Dependency` for all external effects (audio, files, artwork)
- `@Shared(.fileStorage(...))` for session persistence
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

Test reducers with a **non-exhaustive `TestStore`**:

```swift
let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
    $0.fileManager.listItems = { _ in [] }
}
store.exhaustivity = .off          // assert one thing, don't match every effect
await store.send(.recording(.recordingSaved))
XCTAssertFalse(store.state.isRecordingSheetPresented)
```

Never call `SomeFeature().reduce(into:action:)` directly — it is deprecated as of TCA 1.26,
and it bypasses the store, so effects never run and the assertion covers less than it appears to.

## Git Workflow

- **main** - stable branch
- **feat** - active feature development branch
- PRs from `feat` into `main`
