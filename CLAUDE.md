# CLAUDE.md - SonicPlayer

## Project Overview

SonicPlayer is a native iOS audio player app (iOS 18.0+) built with **SwiftUI** and **The Composable Architecture (TCA)** v1.23.1. It supports browsing, playing, and recording audio files with a minimalist Sonic teal design.

**Bundle ID:** `com.hasan.sonicplayer`

## Build & Run

```bash
# Open in Xcode
open SonicPlayer.xcodeproj

# Build via CLI (iPhone simulator)
xcodebuild -project SonicPlayer.xcodeproj -scheme SonicPlayer -destination 'platform=iOS Simulator,name=iPhone 16' build

# SPM dependencies resolve automatically on first build
```

No CocoaPods or Carthage. All dependencies managed via Swift Package Manager.

## Architecture

**TCA (The Composable Architecture)** with strict unidirectional data flow:

- **Features/** - Each feature has a `{Name}Feature.swift` (reducer) and `{Name}View.swift` (UI)
- **Clients/** - Dependency-injected wrappers around system frameworks (AVFoundation, FileManager)
- **Models/** - Plain data types (`AudioFile`, `FileSystemItem`, `PlaybackSpeed`)
- **Utilities/** - Shared UI components and helpers
- **App/** - Root `AppFeature` composes all child reducers; `AppView` is tab-based navigation

### Feature modules
| Feature | Reducer | Purpose |
|---------|---------|---------|
| Home | `HomeFeature` | Folder suggestions, recently added |
| Files | `FilesFeature` | File/folder browser with navigation stack |
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

- **ComposableArchitecture** v1.23.1 (sole third-party dependency)
- All transitive deps (swift-dependencies, swift-perception, swift-navigation, etc.) are pinned in `Package.resolved`

## File Structure

```
SonicPlayer/
  App/           # Entry point, root reducer, root view, quickstart
  Features/      # Home/, Player/, Files/, Recording/, Settings/
  Clients/       # AudioPlayerClient, AudioRecorderClient, FileManagerClient, ArtworkClient, AudioTrimmerClient
  Models/        # AudioFile, FileSystemItem, PlaybackSpeed
  Utilities/     # ColorPalette, Theme, WaveformView, EmptyStateView, ShareSheet, etc.
  Resources/     # Assets.xcassets, Localizable.xcstrings, Quickstart.json, Info.plist
```

## Testing

No test suite yet. The TCA architecture supports testing via `TestStore` - all reducers are testable through dependency injection with mock clients.

## Git Workflow

- **main** - stable branch
- **feat** - active feature development branch
- PRs from `feat` into `main`
