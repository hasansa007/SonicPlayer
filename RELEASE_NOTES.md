# Release Notes

What TestFlight testers see. The distribute workflow reads the section matching
`CFBundleShortVersionString` from `SonicPlayer/Info.plist` — so **add a section here before
bumping the version**, or the build ships with a placeholder.

Written for testers, not for the changelog. Say what changed for someone using the app; leave
refactors, dependency bumps and test work out.

---

## 2.3.0

- Select several files at once in a collection, then move or delete them in one go.
- The Home screen now shows your three most recent recordings rather than ten, so it stays scannable.
- Fixed: deleting or moving the file you were listening to left it playing. Playback now stops.
- Fixed: opening an audio file from the Files app did not always start playing it — most often when
  you had opened that file before. It now plays every time, and tells you if it cannot.

## 2.2.0

- Swipe a file for rename, move, edit and delete without opening it.
- Move files between collections without leaving the app.
- Recordings show a real waveform instead of a placeholder.
- Trimming and range-deletion no longer overwrite the original — edits are non-destructive until you save.

## 2.1.0

- Redesigned onboarding, with a theme picker on the first screen.
- Light, Dark and System themes, switchable any time from Settings.
- Assorted layout and spacing fixes throughout.

## 2.0.0

- Rebuilt around a single screen. The tab bar is gone; the player, recorder and settings now open
  over your library instead of replacing it.
- Collections replace flat folders, with artwork and counts.
