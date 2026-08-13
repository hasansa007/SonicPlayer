# Release Notes

**What TestFlight testers see — not what App Store shoppers see.** The distribute workflow reads
the section matching `CFBundleShortVersionString` from `SonicPlayer/Info.plist` and ships it to
TestFlight, in English only. **Add a section here before bumping the version**, or the run fails
before the archive.

The App Store's *What's New in This Version* is a different field, localised, and no workflow
writes it. That copy lives in `docs/appstore/<version>/` — changing a fact means editing it here
**and** there, in every language present. See `docs/appstore/README.md` for why the split exists.

Written for testers, not for the changelog. Say what changed for someone using the app; leave
refactors, dependency bumps and test work out.

Everything in `CLAUDE.md`'s App Store compliance section binds this file. The app is publicly
listed now, so the five words that never appear are protecting a live listing from removal, not an
upload from rejection.

---

## 3.0.0

The app is one dial now. Everything is done with the wheel and its centre, and there are no other
screens to learn.

- Turn the wheel to move through your library, and press the centre to play what you land on. Keep
  turning past the last row and you reach the buttons under the card.
- Push the centre in a direction for the things you do most to a recording: up to edit it, down to
  delete, left to file it in a folder, right to share. Rest your thumb on the centre for a moment
  and each direction tells you its name before you choose one.
- Record and Import are always to hand, under the card, wherever you are in the library. A recording
  you start inside a folder is now saved in that folder rather than somewhere else.
- Folders, properly: make one, rename it, and move recordings between them. Filing something offers
  a brand-new folder as the first choice, so you can name one and file into it in a single step.
- Each folder keeps its own order, newest or oldest or A to Z or Z to A. Rest on the sort button and
  push the centre towards the order you want. Sorting one folder no longer re-sorts every other.
- Now Playing is the wheel as well: turn to scrub, push up or down for volume, which now moves the
  phone's own volume, and left or right for the previous or next track.
- Editing a recording is a wheel too. Turn to move a handle, hear the selection before you commit to
  it, and keep it or cut it out with one press.
- Turn the phone sideways and the card moves beside the wheel, which stays exactly the size your
  thumb already knows.
- Fixed: recording did nothing the first time you pressed it after installing the app.
- Fixed: importing the same folder twice made a second copy of it. It now merges into the one
  already there.
- Fixed: deleting or moving the file you were listening to left it playing. Playback now stops.
- Fixed: opening an audio file from the Files app did not always start playing it, most often when
  you had opened that file before. It now plays every time, and tells you if it cannot.

If anything on screen cannot be reached by turning the wheel, that is a bug worth reporting. Every
control is meant to be a stop you can turn to.

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
