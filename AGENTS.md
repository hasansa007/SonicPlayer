# AGENTS.md - SonicPlayer

Instructions for AI agents working on this codebase.

## Project Context

This is a SwiftUI iOS app, **mid-migration from TCA to `@Observable` view models** (#5). Some
features are still reducers and some are view models — check which before touching one. Read
`CLAUDE.md` for build instructions, the per-feature migration table, and conventions.

## Rules for All Agents

1. **Read before writing.** Always read the relevant feature files before making changes, and check
   whether the feature is a `{Name}Feature.swift` (reducer) or a `{Name}ViewModel.swift` (migrated).
2. **Match the feature you are in.** In a reducer: state changes go through the reducer, side
   effects through `Effect`, dependencies through `@Dependency`. In a view model: mutate properties
   directly, use `Task` for async work, and take clients as init parameters defaulting to `.live` —
   there is no `@Dependency` in a view model. **Do not migrate a feature as a side effect of an
   unrelated change**; the migration is sliced into its own issues.
3. **Match existing style.** Look at neighboring files for naming, indentation, and structure conventions before writing new code.
4. **Localize all strings.** Every user-facing string must be added to `Localizable.xcstrings` for all 9 supported languages.
5. **Use the design system.** Colors from `ColorPalette.swift`, styles from `Theme.swift`, empty states from `EmptyStateView.swift`.
6. **Don't break the build.** Verify changes compile. If adding new files, ensure they are added to the Xcode project.
7. **Minimal changes.** Don't refactor surrounding code or add features beyond what was requested.

## Agent-Specific Guidelines

### Feature Development

New features go the migrated way — do not add reducers to a codebase that is removing them:
- Create `{Name}ViewModel.swift`: a `@MainActor @Observable final class` taking its clients as init
  parameters defaulting to `.live`
- Create `{Name}View.swift` taking the view model as a plain `let` property
- Own the view model in `AppView` as `@State`, and wire its callbacks in `AppView.wireViewModels()`
- Cross-feature communication travels through a **closure wired at that composition root**, never by
  reading another feature's state
- Create any needed clients in `Clients/` with both live and test implementations

### Bug Fixes

- Reproduce the issue by understanding the state flow — in the reducer, or in the view model
- Fix it there, not by patching the view
- Check for similar patterns in other features that might have the same bug

### UI Changes

- Use SwiftUI previews to iterate
- Support both light and dark mode (use `ColorPalette` adaptive colors)
- Handle empty states, loading states, and error states
- Consider landscape orientation (PlayerView already supports it)
- Test with RTL languages (Arabic is supported)

### Recording Feature

- Audio recording uses `AudioRecorderClient` wrapping `AVAudioRecorder`
- Trimming uses `AudioTrimmerClient`
- Recordings are stored in the app's documents directory
- The `EditRecordingView` handles audio editing after capture

### Player Feature

- The player is `PlayerViewModel` — migrated in #15. `PlayerFeature` no longer exists
- Session state persists via `SessionStore`, which replaced `@Shared(.fileStorage(...))`. Its path
  and JSON shape are a **compatibility boundary**: existing installs have a `session.json`, so
  changing either stops playback resuming after an update
- Queue sequencing decisions live in `Domain/QueueMath.swift`, not in the view model
- Lock screen / remote controls are managed via `MPRemoteCommandCenter`
- Background audio is enabled in `Info.plist`
- `AudioPlayerClient` wraps a process-lifetime `AVPlayer` shared with the recording editor. That is
  why `stop()` is called before any file move — keep those calls

### File Management

- `FileManagerClient` provides all file system operations
- Files are identified by SHA256 hash of their path (stable IDs)
- Supported formats: MP3, M4A, WAV
- File sharing is enabled via `Info.plist` (`UIFileSharingEnabled`)

## Build Verification

After making changes, verify the build:
```bash
xcodebuild -project SonicPlayer.xcodeproj -scheme SonicPlayer -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation build 2>&1 | tail -5
```

A successful build ends with `** BUILD SUCCEEDED **`.
