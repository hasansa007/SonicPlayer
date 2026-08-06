# AGENTS.md - SonicPlayer

Instructions for AI agents working on this codebase.

## Project Context

This is a **SwiftUI + TCA** iOS app. Read `CLAUDE.md` for build instructions, architecture, and conventions.

## Rules for All Agents

1. **Read before writing.** Always read the relevant feature files before making changes. Understand the existing TCA reducer/view pattern.
2. **Follow TCA patterns.** All state changes go through reducers. All side effects use `Effect`. Inject dependencies via `@Dependency`.
3. **Match existing style.** Look at neighboring files for naming, indentation, and structure conventions before writing new code.
4. **Localize all strings.** Every user-facing string must be added to `Localizable.xcstrings` for all 9 supported languages.
5. **Use the design system.** Colors from `ColorPalette.swift`, styles from `Theme.swift`, empty states from `EmptyStateView.swift`.
6. **Don't break the build.** Verify changes compile. If adding new files, ensure they are added to the Xcode project.
7. **Minimal changes.** Don't refactor surrounding code or add features beyond what was requested.

## Agent-Specific Guidelines

### Feature Development

When adding a new feature:
- Create `{Name}Feature.swift` with `@Reducer` struct containing `State`, `Action`, and `body`
- Create `{Name}View.swift` with the SwiftUI view accepting `Store<{Name}Feature.State, {Name}Feature.Action>`
- Add the feature as a child in `AppFeature.swift` using `Scope`
- Add a new tab or navigation destination in `AppView.swift` if needed
- Create any needed clients in `Clients/` with both live and test implementations

### Bug Fixes

- Reproduce the issue by understanding the state flow in the reducer
- Fix in the reducer logic, not by patching the view
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

- Session state persists via `@Shared(.fileStorage(...))` in `PlayerFeature`
- Lock screen / remote controls are managed via `MPRemoteCommandCenter`
- Background audio is enabled in `Info.plist`
- Queue management and track navigation are in `PlayerFeature.swift`

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
